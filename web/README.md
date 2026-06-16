# Podplane Web Template

The `web` template deploys a HTTP web application behind the Podplane ingress stack.

It creates:

- a Deployment running the app container and Caddy sidecar
- a ClusterIP Service on HTTPS port 443
- a Gateway API HTTPRoute
- a cert-manager Certificate for gateway-to-service TLS

The application container should listen for plain HTTP on `app.port` (default: 80). The Caddy sidecar terminates TLS and proxies traffic to the app.

## Values

| Value | Default | Description |
| --- | --- | --- |
| `images.app` | `ghcr.io/podplane/hello:latest` | App container image |
| `images.caddy` | `docker.io/library/caddy:2` | Caddy sidecar image |
| `app.env` | `{}` | Non-secret environment variables for the app container |
| `app.port` | `80` | Plain HTTP port exposed by the app container |
| `route.hostname` | `""` | Optional external hostname for routing |
| `route.path` | `/` | URL path prefix for routing |
| `route.port` | `443` | External HTTPS port for the browser-facing route URL |
| `metrics.http` | `true` | Enable Caddy HTTP metrics |

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

When `route.hostname` is set, Helm prints the external app URL after install or upgrade.

## License

Podplane is licensed under the Apache License, Version 2.0.
Copyright 2026 Nadrama Pty Ltd.
