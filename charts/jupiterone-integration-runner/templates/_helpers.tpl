{{/*
A string map as quoted "key: value" lines, each starting with a newline, or
nothing when empty. A key with no value becomes "". Takes (dict "map" m
"skipHelm" bool "skipReserved" bool): skipHelm drops helm.sh/ and meta.helm.sh/
keys (Helm acts on them, for example helm.sh/resource-policy); skipReserved
drops keys the operator manages on the objects it creates for runs.
*/}}
{{- define "runner.metadataLines" -}}
{{- $skipHelm := .skipHelm -}}
{{- $skipReserved := .skipReserved -}}
{{- $reserved := list "app.kubernetes.io/name" "log-watcher" "job-name" "controller-uid" -}}
{{- range $k, $v := (.map | default dict) }}
{{- $skip := and $skipHelm (or (hasPrefix "helm.sh/" $k) (hasPrefix "meta.helm.sh/" $k)) -}}
{{- if and $skipReserved (or (has $k $reserved) (hasPrefix "batch.kubernetes.io/" $k) (hasPrefix "integrations.jupiterone.io/" $k)) -}}
{{- $skip = true -}}
{{- end -}}
{{- if not $skip }}
{{ $k | quote }}: {{ ternary "" (toString $v) (kindIs "invalid" $v) | quote }}
{{- end }}
{{- end }}
{{- end }}


{{/*
labels: and annotations: blocks from commonLabels and commonAnnotations, for
an object's metadata. Include with: {{- include "runner.metadata" . | nindent 2 }}
*/}}
{{- define "runner.metadata" -}}
{{- with (include "runner.metadataLines" (dict "map" .Values.commonLabels) | trim) }}
labels:
  {{- . | nindent 2 }}
{{- end }}
{{- with (include "runner.metadataLines" (dict "map" .Values.commonAnnotations "skipHelm" true) | trim) }}
annotations:
  {{- . | nindent 2 }}
{{- end }}
{{- end }}
