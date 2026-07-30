# Podplane Web Template

The `web` template deploys a HTTP web application behind the Podplane ingress stack.

It creates:

- a Deployment running the app container and, by default, a Caddy sidecar
- a ClusterIP Service on HTTPS port 443
- a Gateway API HTTPRoute
- a serving certificate delivered by the cert-manager CSI driver by default, or by a cert-manager Certificate and Secret
- optionally, a client certificate for authenticating outbound connections to other cluster services
- optionally, additional cluster-internal Service ports that target the app directly
- optionally, Podplane `SecretProviderBinding` resources and read-only Secrets Store CSI volumes

By default, the application container listens for plain HTTP on `app.port` (default: 8080), while Caddy terminates service TLS and proxies traffic to it. Set `certificates.server=direct` when the app should receive the serving certificate and terminate public service TLS itself.

## Values

| Value | Default | Description |
| --- | --- | --- |
| `images.app` | `ghcr.io/podplane/hello:latest` | App container image |
| `images.caddy` | `docker.io/library/caddy:2` | Caddy sidecar image |
| `app.env` | `{}` | Non-secret environment variables for the app container |
| `app.port` | `8080` | App port, or an array with the primary port first and additional Service ports after it |
| `route.hostname` | `""` | Optional external hostname for routing |
| `route.path` | `/` | URL path prefix for routing |
| `route.port` | `443` | External HTTPS port for the browser-facing route URL |
| `metrics.http` | `true` | Enable Caddy HTTP metrics |
| `serviceAccount.create` | `true` | Create the workload service account when secret mounts are enabled |
| `serviceAccount.name` | `""` | Service account name; defaults to the release-derived app name |
| `secrets` | `[]` | SecretProviderBinding resources to render and mount |
| `secrets[].bindingName` | required | SecretProviderBinding name; the operator generates a same-name SecretProviderClass |
| `secrets[].providerName` | required | Cluster-local Podplane secrets provider name |
| `secrets[].mountPath` | required | Read-only path where secret files are mounted in the app container |
| `secrets[].items` | required | Podplane-managed secret items to mount |
| `secrets[].items[].key` | required | Podplane logical secret key and backend identifier |
| `secrets[].items[].path` | defaults to `key` | Mounted relative path inside `mountPath` |
| `secrets[].syncToKubernetesSecrets` | `[]` | Advanced opt-in sync to native Kubernetes Secrets |
| `secrets[].syncToKubernetesSecrets[].labels` | `{}` | Labels copied to the synced Kubernetes Secret |
| `secrets[].syncToKubernetesSecrets[].annotations` | `{}` | Annotations copied to the synced Kubernetes Secret |
| `certificates.server` | `sidecar` | Service TLS handling mode (`sidecar` or `direct`) |
| `certificates.client` | `false` | Issue and mount a client certificate |
| `certificates.secrets` | `false` | Create cert-manager Certificate Secrets instead of pod-local CSI certificates |

## Server certificate

Certificate delivery and service TLS handling are independent choices.

By default, the template requests pod-local certificates from the cert-manager CSI driver. It does not create cert-manager `Certificate` resources or Kubernetes Secrets, and the driver rotates the mounted files. Set `certificates.secrets=true` to create cert-manager `Certificate` resources and mount their generated Secrets instead. Both approaches expose `tls.crt`, `tls.key`, and `ca.crt`; Caddy or the app must handle rotated files appropriately. Caddy does not currently reload externally rotated certificate files automatically, so sidecar mode continues using its in-memory certificate until Caddy or the Pod restarts; see [caddyserver/caddy#6933](https://github.com/caddyserver/caddy/issues/6933). In direct mode, the serving files are always mounted at `/var/run/secrets/podplane/server-certificate`.

In the default `certificates.server=sidecar` mode, the public Service targets Caddy on port 443 and Caddy proxies plain HTTP to the primary app port. In `direct` mode, the Caddy sidecar and configuration are omitted, the public Service targets the primary app port, and the serving certificate is mounted into the app at `/var/run/secrets/podplane/server-certificate`. The app must serve TLS and reload rotated certificate files in direct mode.

## Client certificate

When `certificates.client` is true, the template requests a certificate with the `client auth` extended key usage and exactly one namespace-qualified, release-derived DNS SAN. Both delivery methods mount `tls.crt`, `tls.key`, and the issuer-provided `ca.crt` when available at `/var/run/secrets/podplane/client-certificate`. For example, a release named `example-api` in the `production` namespace receives the client identity `example-api.production`. This is independent of serving-certificate delivery and service TLS handling.

Certificate handling is shared with the serving certificate. CSI gives every Pod a unique node-local private key and automatically renewed certificate without creating a Kubernetes Secret. Setting `certificates.secrets=true` instead creates a cert-manager `Certificate` and mounts its persistent Secret; use it when the CSI driver is unavailable or credentials must persist or be shared. Both approaches renew certificates, so long-running applications must reload mounted TLS material after rotation.

## Additional Service ports

Set `app.port` to an array to expose additional Service ports. The first item remains the primary port used by Caddy or the public Service; every later port is exposed directly and receives a generated name such as `port-8082`. Additional ports cannot use the public Service port 443 and are not referenced by the HTTPRoute. The app owns their protocol and any authentication or authorization.

For example, an app serving public TLS directly on port 8080 and internal mTLS on port 8082 uses:

```yaml
app:
  port: [8080, 8082]
certificates:
  server: direct
```

## Example

```sh
helm upgrade --install hello oci://ghcr.io/podplane/web \
  --version 1.0.0 \
  --set images.app=ghcr.io/podplane/hello:latest \
  --set route.hostname=hello.example.com
```

Podplane normally installs this chart through:

```sh
podplane deploy web --name hello --image ghcr.io/podplane/hello:latest
```

Use quoted Helm list syntax when setting multiple app ports through Podplane:

```sh
podplane deploy web --name hello --set 'app.port={8080,8082}'
```

When `route.hostname` is set, Helm prints the external app URL after install or upgrade.

## License

Podplane is licensed under the Apache License, Version 2.0.
Copyright The Podplane Authors.
