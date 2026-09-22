{{- define "chart.name" -}}
{{- if .Values.nameOverride }}
  {{- .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- else if and .Chart .Chart.Name }}
  {{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
  jupiterone-integration-operator
{{- end }}
{{- end }}


{{- define "chart.labels" -}}
{{- if .Chart.AppVersion -}}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- if .Chart.Version }}
helm.sh/chart: {{ .Chart.Version | quote }}
{{- end }}
app.kubernetes.io/name: {{ include "chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}


{{- define "chart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "chart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}


{{- define "chart.hasMutatingWebhooks" -}}
{{- $hasMutating := false }}
{{- range . }}
  {{- if eq .type "mutating" }}
    $hasMutating = true }}{{- end }}
{{- end }}
{{ $hasMutating }}}}{{- end }}


{{- define "chart.hasValidatingWebhooks" -}}
{{- $hasValidating := false }}
{{- range . }}
  {{- if eq .type "validating" }}
    $hasValidating = true }}{{- end }}
{{- end }}
{{ $hasValidating }}}}{{- end }}


{{- define "chart.integrationJobServiceAccountName" -}}
{{- if .Values.integration.jobServiceAccount.name -}}
{{- .Values.integration.jobServiceAccount.name -}}
{{- else if .Values.integration.jobServiceAccount.create -}}
jupiterone-integration-job
{{- end -}}
{{- end }}
