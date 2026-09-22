{{/*
Expand the worker name into a Kubernetes-safe base name.
*/}}
{{- define "worker.name" -}}
{{- $name := regexReplaceAll "[^a-z0-9-]" (.Release.Name | lower) "-" | trimAll "-" -}}
{{- $name = default .Chart.Name $name -}}
{{- if not (regexMatch "^[a-z]" $name) -}}
{{- $name = printf "%s-%s" .Chart.Name $name -}}
{{- end -}}
{{- $name | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{- define "worker.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "worker.labels" -}}
helm.sh/chart: {{ include "worker.chart" . | quote }}
app.kubernetes.io/name: {{ include "worker.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end -}}

{{- define "worker.selectorLabels" -}}
app.kubernetes.io/name: {{ include "worker.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end -}}

{{- define "worker.serviceAccountName" -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- include "worker.name" . -}}
{{- end -}}
{{- end -}}

{{/* Render an enabled exec probe. */}}
{{- define "worker.execProbe" -}}
exec:
  command:
    {{- toYaml (required "an enabled probe requires command" .command) | nindent 4 }}
initialDelaySeconds: {{ .initialDelaySeconds }}
periodSeconds: {{ .periodSeconds }}
timeoutSeconds: {{ .timeoutSeconds }}
successThreshold: {{ .successThreshold }}
failureThreshold: {{ .failureThreshold }}
{{- end -}}
