// Podplane <https://podplane.dev>
// Copyright 2026 Nadrama Pty Ltd
// SPDX-License-Identifier: Apache-2.0
//
// Generates template image metadata in manifests/templates.json.

package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

var outputPath = flag.String("output", "manifests/templates.json", "Path to write the template manifest JSON.")

type manifest struct {
	Templates templates `json:"templates"`
}

type templates struct {
	Version string          `json:"version"`
	Charts  []templateChart `json:"charts"`
	Images  []image         `json:"images,omitempty"`
}

type templateChart struct {
	Name         string         `json:"name"`
	Version      string         `json:"version"`
	Type         string         `json:"type"`
	URL          string         `json:"url,omitempty"`
	Path         string         `json:"path,omitempty"`
	Digest       string         `json:"digest,omitempty"`
	Dependencies map[string]any `json:"dependencies,omitempty"`
}

type image struct {
	Image     string            `json:"image"`
	Digest    string            `json:"digest"`
	Size      int64             `json:"size"`
	Platform  string            `json:"platform,omitempty"`
	Index     string            `json:"index,omitempty"`
	Templates map[string]string `json:"templates"`
}

type imageRef struct {
	Image    string
	Template string
	Key      string
}

type imageIndex struct {
	Manifests []struct {
		Digest   string `json:"digest"`
		Platform struct {
			OS           string `json:"os"`
			Architecture string `json:"architecture"`
			Variant      string `json:"variant,omitempty"`
		} `json:"platform"`
	} `json:"manifests"`
}

func main() {
	flag.Parse()
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run() error {
	raw, err := os.ReadFile(*outputPath)
	if err != nil {
		return fmt.Errorf("read %s: %w", *outputPath, err)
	}
	var m manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		return fmt.Errorf("parse %s: %w", *outputPath, err)
	}
	if version := os.Getenv("VERSION"); version != "" {
		m.Templates.Version = version
	}
	if m.Templates.Version == "" {
		m.Templates.Version = "dev"
	}

	refs, err := readImageRefs(m.Templates.Charts)
	if err != nil {
		return err
	}
	images, err := resolveImages(refs)
	if err != nil {
		return err
	}
	m.Templates.Images = images

	out, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return fmt.Errorf("encode manifest: %w", err)
	}
	out = append(out, '\n')
	if err := os.WriteFile(*outputPath, out, 0o644); err != nil {
		return fmt.Errorf("write %s: %w", *outputPath, err)
	}
	fmt.Printf("wrote %s (%d images)\n", *outputPath, len(images))
	return nil
}

func readImageRefs(charts []templateChart) ([]imageRef, error) {
	refs := []imageRef{}
	for _, chart := range charts {
		if chart.Name == "" || chart.Path == "" {
			continue
		}
		valuesPath := filepath.Join("manifests", chart.Path, "values.yaml")
		valuesPath, err := filepath.Abs(valuesPath)
		if err != nil {
			return nil, err
		}
		imagesJSON, err := commandOutput("yq", "e", "-o=json", ".images // {}", valuesPath)
		if err != nil {
			return nil, fmt.Errorf("read images from %s: %w", valuesPath, err)
		}
		images := map[string]string{}
		if err := json.Unmarshal([]byte(imagesJSON), &images); err != nil {
			return nil, fmt.Errorf("parse images from %s: %w", valuesPath, err)
		}
		for key, ref := range images {
			if ref == "" {
				continue
			}
			refs = append(refs, imageRef{Image: ref, Template: chart.Name, Key: key})
		}
	}
	return refs, nil
}

func resolveImages(refs []imageRef) ([]image, error) {
	byImage := map[string][]imageRef{}
	for _, ref := range refs {
		byImage[ref.Image] = append(byImage[ref.Image], ref)
	}
	sources := make([]string, 0, len(byImage))
	for source := range byImage {
		sources = append(sources, source)
	}
	sort.Strings(sources)

	images := []image{}
	for _, source := range sources {
		fmt.Fprintf(os.Stderr, "resolving image: %s\n", source)
		resolved, err := resolveImage(source, byImage[source])
		if err != nil {
			return nil, err
		}
		images = append(images, resolved...)
	}
	sort.Slice(images, func(i, j int) bool {
		if images[i].Image != images[j].Image {
			return images[i].Image < images[j].Image
		}
		return images[i].Platform < images[j].Platform
	})
	return images, nil
}

func resolveImage(source string, refs []imageRef) ([]image, error) {
	indexDigest, err := commandOutput("crane", "digest", source)
	if err != nil {
		return nil, fmt.Errorf("resolve digest for %s: %w", source, err)
	}
	indexDigest = strings.TrimSpace(indexDigest)
	indexRaw, err := commandOutput("crane", "manifest", source+"@"+indexDigest)
	if err != nil {
		return nil, fmt.Errorf("inspect manifest for %s: %w", source, err)
	}

	var idx imageIndex
	if err := json.Unmarshal([]byte(indexRaw), &idx); err != nil {
		return nil, fmt.Errorf("parse manifest for %s: %w", source, err)
	}
	if len(idx.Manifests) == 0 {
		size, err := manifestSize([]byte(indexRaw))
		if err != nil {
			return nil, fmt.Errorf("calculate image size for %s: %w", source, err)
		}
		return []image{{Image: source, Digest: indexDigest, Size: size, Templates: templateMap(refs)}}, nil
	}

	images := []image{}
	for _, child := range idx.Manifests {
		platform := platformString(child.Platform.OS, child.Platform.Architecture, child.Platform.Variant)
		if !supportedPlatform(platform) {
			continue
		}
		childRaw, err := commandOutput("crane", "manifest", source+"@"+child.Digest)
		if err != nil {
			return nil, fmt.Errorf("inspect child manifest %s: %w", child.Digest, err)
		}
		size, err := manifestSize([]byte(childRaw))
		if err != nil {
			return nil, fmt.Errorf("calculate image size for %s: %w", child.Digest, err)
		}
		images = append(images, image{Image: source, Digest: child.Digest, Size: size, Platform: platform, Index: indexDigest, Templates: templateMap(refs)})
	}
	if len(images) == 0 {
		return nil, fmt.Errorf("%s has no supported linux/amd64 or linux/arm64 platform", source)
	}
	return images, nil
}

func templateMap(refs []imageRef) map[string]string {
	out := map[string]string{}
	for _, ref := range refs {
		out[ref.Template] = ref.Key
	}
	return out
}

func platformString(osName, arch, variant string) string {
	if variant != "" {
		return osName + "/" + arch + "/" + variant
	}
	return osName + "/" + arch
}

func supportedPlatform(platform string) bool {
	return platform == "linux/amd64" || platform == "linux/arm64" || platform == "linux/arm64/v8"
}

func manifestSize(body []byte) (int64, error) {
	var manifest struct {
		Config *struct {
			Size int64 `json:"size"`
		} `json:"config"`
		Layers []struct {
			Size int64 `json:"size"`
		} `json:"layers"`
	}
	if err := json.Unmarshal(body, &manifest); err != nil {
		return 0, err
	}
	size := int64(len(body))
	if manifest.Config != nil {
		size += manifest.Config.Size
	}
	for _, layer := range manifest.Layers {
		size += layer.Size
	}
	return size, nil
}

func commandOutput(name string, args ...string) (string, error) {
	cmd := exec.Command(name, args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(stderr.String()))
	}
	return string(out), nil
}
