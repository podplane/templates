{{/*
Expand the app name into a Kubernetes-safe base name.
*/}}
{{- define "web.name" -}}
{{- $name := regexReplaceAll "[^a-z0-9-]" (.Release.Name | lower) "-" | trimAll "-" -}}
{{- $name = default .Chart.Name $name -}}
{{- if not (regexMatch "^[a-z]" $name) -}}
{{- $name = printf "%s-%s" .Chart.Name $name -}}
{{- end -}}
{{- $name | trunc 40 | trimSuffix "-" -}}
{{- end -}}

{{- define "web.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "web.labels" -}}
helm.sh/chart: {{ include "web.chart" . | quote }}
app.kubernetes.io/name: {{ include "web.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service | quote }}
{{- end -}}

{{- define "web.selectorLabels" -}}
app.kubernetes.io/name: {{ include "web.name" . | quote }}
app.kubernetes.io/instance: {{ .Release.Name | quote }}
{{- end -}}
