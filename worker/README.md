# Podplane Worker Template

The `worker` template deploys a long-running background process with no Service, ingress, or server TLS resources.

It creates:

- a Deployment running the worker container
- a writable temporary work volume
- a NetworkPolicy that denies ingress and allows egress by default
- optionally, a dedicated or existing ServiceAccount
- optionally, Podplane `SecretProviderBinding` resources and read-only Secrets Store CSI volumes
- optionally, read-only Kubernetes image volumes containing separately versioned OCI content
- optionally, a cert-manager CSI or Secret-backed client certificate mounted read-only for mTLS authentication

The default single replica uses the `Recreate` deployment strategy so an update does not briefly overlap the old and new worker. Applications remain responsible for graceful shutdown and restart-safe processing.

## Values

| Value | Default | Description |
| --- | --- | --- |
| `images.app` | `ghcr.io/podplane/hello:latest` | Worker container image |
| `images.<key>` | none | Additional image reference used by a matching `imageVolumes[].imageKey` |
| `app.replicas` | `1` | Number of worker replicas |
| `app.strategy` | `Recreate` | Deployment update strategy (`Recreate` or `RollingUpdate`) |
| `app.command` | `[]` | Optional container entrypoint override |
| `app.args` | `[]` | Optional container arguments override |
| `app.env` | `{}` | Non-secret environment variables for the worker container |
| `app.terminationGracePeriodSeconds` | `30` | Pod shutdown grace period |
| `resources` | see `values.yaml` | Worker resource requests and limits |
| `probes.liveness` | disabled | Optional exec liveness probe |
| `probes.readiness` | disabled | Optional exec readiness probe |
| `probes.startup` | disabled | Optional exec startup probe |
| `podSecurityContext` | non-root, RuntimeDefault seccomp | Pod-level security context |
| `containerSecurityContext` | restricted defaults | Worker container security context |
| `workVolume.enabled` | `true` | Mount a writable `emptyDir` temporary work volume |
| `workVolume.mountPath` | `/tmp` | Path of the writable temporary work volume |
| `workVolume.medium` | `""` | Optional `emptyDir` medium, such as `Memory` |
| `workVolume.sizeLimit` | `""` | Optional `emptyDir` size limit |
| `imageVolumes` | `[]` | Read-only Kubernetes image volumes mounted into the worker |
| `imageVolumes[].name` | required | Kubernetes volume name |
| `imageVolumes[].imageKey` | required | Key under `images` containing the OCI image reference |
| `imageVolumes[].mountPath` | required | Absolute read-only mount path in the worker container |
| `imageVolumes[].pullPolicy` | `IfNotPresent` | Image volume pull policy |
| `networkPolicy.enabled` | `true` | Create a NetworkPolicy for the worker |
| `networkPolicy.allowAllEgress` | `true` | Permit all outbound traffic; set false for default-deny egress |
| `serviceAccount.create` | `true` | Create the worker ServiceAccount |
| `serviceAccount.name` | `""` | ServiceAccount name; defaults to the release-derived worker name |
| `serviceAccount.annotations` | `{}` | Annotations for workload identity or other integrations |
| `podAnnotations` | `{}` | Additional Pod annotations |
| `podLabels` | `{}` | Additional Pod labels |
| `secrets` | `[]` | SecretProviderBinding resources to render and mount |
| `certificates.client` | `false` | Issue and mount a client certificate |
| `certificates.secrets` | `false` | Create a cert-manager Certificate Secret instead of a pod-local CSI certificate |

The `secrets` structure is the same as the Podplane `web` template. Secret mounts are read-only and non-secret configuration should use `app.env`.

Image volumes require a Kubernetes cluster with the `ImageVolume` feature available (which is available by default in every Podplane cluster). Each image must be supplied under `images`, then referenced by key:

```yaml
images:
  app: ghcr.io/example/worker@sha256:...
  podplane: ghcr.io/example/podplane-tool@sha256:...
  opentofu: ghcr.io/example/opentofu-tool@sha256:...

imageVolumes:
  - name: podplane
    imageKey: podplane
    mountPath: /opt/podplane
  - name: opentofu
    imageKey: opentofu
    mountPath: /opt/opentofu
```

The worker can use environment variables or arguments to locate files within these mounts. Container runtimes may mount image volumes with execution disabled; applications that need to run mounted content should copy it into the writable work volume and invoke the copy. Content staging and executable-path selection are application concerns rather than template behavior.

## Client certificate

When `certificates.client` is true, the template requests a certificate with the `client auth` extended key usage and exactly one namespace-qualified, release-derived DNS SAN. Both delivery methods mount `tls.crt`, `tls.key`, and the issuer-provided `ca.crt` when available at `/var/run/secrets/podplane/client-certificate`. The default issuer is Podplane's cluster self-signed service issuer. For example, a release named `email-worker` in the `production` namespace receives the client identity `email-worker.production`.

By default, the template uses `csi.cert-manager.io`, giving every Pod a unique node-local private key and automatically renewed certificate without creating a Kubernetes Secret. Setting `certificates.secrets=true` instead creates a cert-manager `Certificate` and mounts its persistent Secret; use it when the CSI driver is unavailable or credentials must persist or be shared. Both approaches renew certificates, so long-running applications must reload mounted TLS material after rotation. CSI certificates require Podplane's cert-manager component, which includes the cert-manager CSI driver; certificate Secrets require cert-manager.

## Example

```sh
helm upgrade --install jobs oci://ghcr.io/podplane/worker \
  --version 1.0.0 \
  --set images.app=ghcr.io/example/worker:latest \
  --set app.env.QUEUE=default
```

Podplane normally installs this chart through:

```sh
podplane deploy worker --name jobs --image ghcr.io/podplane/hello:latest -e QUEUE=default
```

## License

Podplane is licensed under the Apache License, Version 2.0.
Copyright The Podplane Authors.
