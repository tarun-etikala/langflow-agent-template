{{/*
Chart name, truncated to 63 chars (K8s label limit).
*/}}
{{- define "langflow-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. Uses release name + chart name.
*/}}
{{- define "langflow-agent.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s" .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "langflow-agent.labels" -}}
helm.sh/chart: {{ include "langflow-agent.name" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: langflow-agent
{{- end }}

{{/*
Selector labels — used in matchLabels for deployments/services.
*/}}
{{- define "langflow-agent.selectorLabels" -}}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: langflow-agent
{{- end }}

{{/*
PostgreSQL connection URL — used by Langflow and MLflow.
*/}}
{{- define "langflow-agent.postgresUrl" -}}
postgresql://{{ .Values.global.postgresql.username }}:{{ .Values.global.postgresql.password }}@{{ .Release.Name }}-postgresql:5432/{{ .Values.global.postgresql.database }}
{{- end }}
