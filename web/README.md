# Podplane Web Template

The `web` template deploys a HTTP web application behind the Podplane ingress stack.

It creates:

- a Deployment running the app container and, by default, an Envoy sidecar
- a ClusterIP Service on HTTPS port 443
- a Gateway API HTTPRoute
- an automatically rotating Kubernetes pod certificate authorized for the release Service
- optionally, a ServiceAccount SPIFFE identity and workload trust bundle for outbound mTLS
- optionally, additional cluster-internal Service ports that target the app directly
- optionally, Podplane `SecretProviderBinding` resources and read-only Secrets Store CSI volumes

By default, the application container listens for plain HTTP on `app.port` (default: 8080), while Envoy terminates service TLS and proxies traffic to it. Set `certificates.server=direct` when the app should receive the serving certificate and terminate public service TLS itself.

## Values

| Value | Default | Description |
| --- | --- | --- |
| `images.app` | `ghcr.io/podplane/hello:latest` | App container image |
| `images.envoy` | `docker.io/envoyproxy/envoy:distroless-v1.37-latest` | Envoy sidecar image |
| `app.env` | `{}` | Non-secret environment variables for the app container |
| `app.port` | `8080` | App port, or an array with the primary port first and additional Service ports after it |
| `route.hostname` | `""` | Optional external hostname for routing |
| `route.path` | `/` | URL path prefix for routing |
| `route.port` | `443` | External HTTPS port for the browser-facing route URL |
| `serviceAccount.create` | `true` | Create the workload service account |
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
| `certificates.client` | `false` | Project and mount a ServiceAccount SPIFFE identity and workload trust bundle |

## Server certificate

The template requests a serving certificate through a Kubernetes pod certificate projection. The request uses the `certificates.podplane.dev/workload` signer and identifies the release Service that the certificate must be valid for. The Podplane operator only signs the request when that Service selects the requesting Pod, preventing a workload from requesting a certificate for an unrelated Service.

The private key remains local to the Pod and is never stored in a Kubernetes Secret or another API object. Kubernetes renews the certificate and atomically updates the projected files before it expires. No cert-manager resource is created, and applications do not need to persist certificate state between Pods.

In the default `certificates.server=sidecar` mode, the public Service targets Envoy on port 8443 and Envoy proxies plain HTTP to the primary app port. Kubernetes mounts the private key and certificate chain together at `/var/run/secrets/podplane/server-certificate/credential-bundle.pem`. Envoy reads both from that file, while its filesystem SDS watches the projected directory and adopts rotated credentials without restarting the Pod. An invalid update leaves the previous valid TLS context active. The application receives plain HTTP from Envoy and does not need to load the serving certificate itself.

In `direct` mode, the Envoy sidecar and configuration are omitted and the public Service targets the primary app port. The same `credential-bundle.pem` is mounted into the application instead. The application must terminate TLS, watch the projected directory, and reload the credential after rotation. The serving projection does not include trust roots; those are mounted only when the optional client identity is enabled.

The chart's `BackendTLSPolicy` tells Envoy Gateway how to verify the serving certificate when it connects to the Service. It references the workload CA published by the operator as `ClusterTrustBundle/certificates.podplane.dev:workload:roots`, so the chart does not need to copy the CA into a namespace-local ConfigMap.

## Client certificate

Set `certificates.client=true` when the application needs a workload identity for outbound mTLS connections. This creates a second pod certificate projection for the workload service account; it is independent of the serving certificate and does not change how inbound TLS is terminated.

The identity is a SPIFFE X.509-SVID with an ID in the form `spiffe://<trust-domain>/ns/<namespace>/sa/<service-account>`. For example, an `example-api` ServiceAccount in the `production` namespace receives an identity ending in `/ns/production/sa/example-api`. The private key and certificate chain are mounted together at `/var/run/secrets/podplane/client-certificate/credential-bundle.pem`, and the workload CA roots are mounted alongside them at `trust-bundle.pem`.

Both files are projected directly into the Pod and are never backed by Kubernetes Secrets. Kubernetes rotates them automatically, so a long-running application must watch the projected directory and reload its identity and trust roots after updates. The application remains responsible for validating peer certificates and authorizing their SPIFFE identities.

## Additional Service ports

Set `app.port` to an array to expose additional Service ports. The first item remains the primary port used by Envoy or the public Service; every later port is exposed directly and receives a generated name such as `port-8082`. Additional ports cannot use the public Service port 443 and are not referenced by the HTTPRoute. The app owns their protocol and any authentication or authorization.

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
