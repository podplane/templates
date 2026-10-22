#!/usr/bin/env bash
# Podplane <https://podplane.dev>
# Copyright The Podplane Authors
# SPDX-License-Identifier: Apache-2.0
#
# Rendering tests for the template charts.

set -euo pipefail

KUBE_VERSION="${KUBE_VERSION:-1.37.0}"
failed=0

fail() {
    echo "FAIL: $*" >&2
    failed=1
}

# runtime_class <chart> [helm args...] prints the Deployment's Pod RuntimeClass.
runtime_class() {
    local chart="$1"
    shift
    helm template test "${chart}" --kube-version "${KUBE_VERSION}" "$@" |
        yq e 'select(.kind == "Deployment") | .spec.template.spec.runtimeClassName' -
}

for chart in web worker; do
    # Templates must name a runtime rather than fall back to the node default.
    got=$(runtime_class "${chart}")
    [ "${got}" = gvisor ] || fail "${chart}: default runtimeClassName = ${got}, want gvisor"
    got=$(runtime_class "${chart}" --set runtimeClassName=runc)
    [ "${got}" = runc ] || fail "${chart}: runtimeClassName=runc rendered ${got}"
    for value in '""' null kata gVisor; do
        if runtime_class "${chart}" --set "runtimeClassName=${value}" >/dev/null 2>&1; then
            fail "${chart}: runtimeClassName=${value} passed chart validation"
        fi
    done
done

# Binary is presence-sensitive. Provider names are opaque references: the
# operator, not the chart, validates the effective provider's capabilities.
for chart in web worker; do
    for provider in omitted custom-provider; do
        args=(--set 'secrets[0].bindingName=test-secret' --set 'secrets[0].mountPath=/secrets' --set 'secrets[0].items[0].key=credential')
        if [ "${provider}" != omitted ]; then
            args+=(--set "secrets[0].providerName=${provider}")
        fi
        for binary in omitted true false; do
            binary_args=()
            if [ "${binary}" != omitted ]; then
                binary_args+=(--set "secrets[0].items[0].binary=${binary}")
            fi
            binding=$(helm template test "${chart}" --kube-version "${KUBE_VERSION}" "${args[@]}" "${binary_args[@]}" |
                yq e 'select(.kind == "SecretProviderBinding")' -)
            expected_provider="${provider}"
            [ "${provider}" != omitted ] || expected_provider=null
            [ "$(yq e '.spec.providerName' - <<<"${binding}")" = "${expected_provider}" ] ||
                fail "${chart}: provider ${provider} was not preserved"
            if [ "${binary}" = omitted ]; then
                [ "$(yq e '.spec.items[0] | has("binary")' - <<<"${binding}")" = false ] ||
                    fail "${chart}: omitted binary was rendered (${provider})"
            else
                [ "$(yq e '.spec.items[0].binary | tag' - <<<"${binding}")" = '!!bool' ] &&
                    [ "$(yq e '.spec.items[0].binary' - <<<"${binding}")" = "${binary}" ] ||
                    fail "${chart}: binary ${binary} was not preserved (${provider})"
            fi
        done
        for value in '"true"' '"false"' '1' '[]' '{}'; do
            if helm template test "${chart}" --kube-version "${KUBE_VERSION}" "${args[@]}" \
                --set-json "secrets[0].items[0].binary=${value}" >/dev/null 2>&1; then
                fail "${chart}: nonboolean binary ${value} passed validation (${provider})"
            fi
        done
    done
done

# web's sidecar mode must not wait for inotify events on the projected
# certificate, which gVisor does not deliver for kubelet's updates. Envoy watches
# a Pod-shared volume where the reloader sidecar renames a marker file instead.
rendered=$(helm template test web --kube-version "${KUBE_VERSION}")
secret=$(yq e 'select(.kind == "ConfigMap") | .data["server-certificate.yaml"]' - <<<"${rendered}")
deployment=$(yq e 'select(.kind == "Deployment")' - <<<"${rendered}")
[ "$(yq e '.resources[0].tls_certificate.watched_directory.path' - <<<"${secret}")" = /var/run/podplane/certificate-reload ] ||
    fail "web: Envoy does not watch the certificate reload volume"
[ "$(yq e '.resources[0].tls_certificate.private_key.filename' - <<<"${secret}")" = /var/run/secrets/podplane/server-certificate/credential-bundle.pem ] ||
    fail "web: Envoy does not read the projected certificate"
yq e '.spec.template.spec.containers[] | select(.name == "test-certificate-reloader") | .command[2]' - <<<"${deployment}" |
    grep -q 'mv .*/certificate-reload/rotated' || fail "web: reloader does not rename into the reload volume"
for key in share=pod type=tmpfs; do
    [ "$(yq e ".spec.template.metadata.annotations[\"dev.gvisor.spec.mount.certificate-reload.${key%%=*}\"]" - <<<"${deployment}")" = "${key#*=}" ] ||
        fail "web: reload volume is not shared under gVisor (${key})"
done
if yq e '.spec.template.spec.containers[].volumeMounts[] | select(.name == "certificate-reload") | .mountPath' - <<<"${deployment}" | grep -q '/$'; then
    fail "web: gVisor cannot share a mount path ending in /"
fi
# Under runc, inotify sees kubelet's updates, so Envoy watches the projected
# certificate directly and the chart renders no reloader.
runc=$(helm template test web --kube-version "${KUBE_VERSION}" --set runtimeClassName=runc)
[ "$(yq e 'select(.kind == "ConfigMap") | .data["server-certificate.yaml"]' - <<<"${runc}" | yq e '.resources[0].tls_certificate.watched_directory.path' -)" = /var/run/secrets/podplane/server-certificate ] ||
    fail "web: runc Envoy does not watch the projected certificate"
if grep -q certificate-reload <<<"${runc}"; then
    fail "web: runc renders the certificate reloader"
fi
direct=$(helm template test web --kube-version "${KUBE_VERSION}" --set certificates.server=direct | yq e 'select(.kind == "Deployment")' -)
if [ "$(yq e '[.spec.template.spec.containers[].name] | length' - <<<"${direct}")" != 1 ] || grep -q certificate-reload <<<"${direct}"; then
    fail "web: direct mode renders the certificate reloader"
fi

[ "${failed}" = 0 ] && echo "chart tests passed"
exit "${failed}"
