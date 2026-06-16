# Podplane App Templates

This repository contains the Helm charts for all Podplane app templates.

App templates are opinionated Helm charts that make it easy to deploy common workload types via `podplane deploy`.

Each template chart must include a `values.schema.json` file. Podplane uses the schema as the template values contract, including to validate whether common ergonomic deploy flags such as `--hostname` and `--path` are supported by a template.

## Templates Manifest

The checked-in [`manifests/templates.json`](./manifests/templates.json) file is a development manifest. It points at local unpacked Helm chart directories with `type: "chart"`.

Release automation publishes each chart as a Helm OCI artifact, renders a release manifest with `type: "oci"` entries and OCI manifest digests for each chart, then attaches the manifest to the GitHub Release with signed sha512 checksums.

Either the development manifest, or published manifest, can be used with the `podplane deps download` command, specified using the `--templates` flag.

Run `make update-manifests` after changing template image values. This regenerates the manifest image metadata from each chart's `images` values, including per-platform digests and sizes.

## Template Image Contract

Template charts must put every container image value under `images`. The manifest's `templates.images` list contains the resolved source images, per-platform digests, and the template image keys that reference each image.

For example, a chart value at `images.caddy` is represented in the manifest as:

```json
{
  "image": "docker.io/library/caddy:2",
  "digest": "sha256:...",
  "size": 22793195,
  "platform": "linux/arm64/v8",
  "index": "sha256:...",
  "templates": {
    "web": "caddy"
  }
}
```

The `templates` map uses template names as keys and `images.<key>` suffixes as values. Multiple templates may reference the same image.

## Learn More

Read more about how templates work in the Podplane [templates documentation](https://podplane.dev/docs/templates).

Learn more about Podplane at the official project website: [podplane.dev](https://podplane.dev)

## License

Podplane is licensed under the Apache License, Version 2.0.
Copyright 2026 Nadrama Pty Ltd.

See the [LICENSE](./LICENSE) file for details.
