{{- define "chart.name" -}}
{{- if .Values.nameOverride }}
  {{- .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- else if and .Chart .Chart.Name }}
  {{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
  jupiterone-integration-operator
{{- end }}
{{- end }}


{{/*
Labels the chart sets itself. User label maps cannot override these keys.
*/}}
{{- define "chart.ownLabels" -}}
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


{{/*
Label keys the chart sets itself (chart.ownLabels and control-plane), as a
JSON list. They are skipped from commonLabels everywhere, and from the
object-specific label maps on the chart's objects.
*/}}
{{- define "chart.ownKeys" -}}
{{- list "app.kubernetes.io/version" "helm.sh/chart" "app.kubernetes.io/name" "app.kubernetes.io/instance" "app.kubernetes.io/managed-by" "control-plane" | toJson -}}
{{- end }}


{{/*
Every object's labels: the chart's own plus commonLabels.
*/}}
{{- define "chart.labels" -}}
{{ include "chart.ownLabels" . }}
{{- include "chart.userLabels" (dict "ctx" .) }}
{{- end }}


{{/*
User labels: commonLabels overlaid by the optional "specific" map (for
example controllerManager.pod.labels), one quoted "key: value" per line, each
line starting with a newline. Keys the chart sets itself and control-plane are
skipped. A key with no value becomes "". Takes (dict "ctx" $ "specific" map).
*/}}
{{- define "chart.userLabels" -}}
{{- $skip := include "chart.ownKeys" .ctx | fromJsonArray -}}
{{- $m := dict -}}
{{- range $k, $v := (.ctx.Values.commonLabels | default dict) -}}
{{- $_ := set $m $k $v -}}
{{- end -}}
{{- range $k, $v := (.specific | default dict) -}}
{{- $_ := set $m $k $v -}}
{{- end -}}
{{- range $k, $v := $m }}
{{- if not (has $k $skip) }}
{{ $k | quote }}: {{ ternary "" (toString $v) (kindIs "invalid" $v) | quote }}
{{- end }}
{{- end }}
{{- end }}


{{/*
User annotations: commonAnnotations overlaid by the optional "specific" map,
in the same format as chart.userLabels. helm.sh/ and meta.helm.sh/ keys are
dropped from commonAnnotations (Helm acts on them, for example
helm.sh/resource-policy), and kubectl.kubernetes.io/default-container is
skipped (the chart sets it on the manager pod). "skipPrefix" drops keys with
that prefix from both maps. Takes (dict "ctx" $ "specific" map "skipPrefix" s).
*/}}
{{- define "chart.userAnnotations" -}}
{{- $skipPrefix := .skipPrefix -}}
{{- $common := dict -}}
{{- range $k, $v := (.ctx.Values.commonAnnotations | default dict) -}}
{{- if not (or (hasPrefix "helm.sh/" $k) (hasPrefix "meta.helm.sh/" $k)) -}}
{{- $_ := set $common $k $v -}}
{{- end -}}
{{- end -}}
{{- $m := $common -}}
{{- range $k, $v := (.specific | default dict) -}}
{{- $_ := set $m $k $v -}}
{{- end -}}
{{- range $k, $v := $m }}
{{- if not (or (eq $k "kubectl.kubernetes.io/default-container") (and $skipPrefix (hasPrefix $skipPrefix $k))) }}
{{ $k | quote }}: {{ ternary "" (toString $v) (kindIs "invalid" $v) | quote }}
{{- end }}
{{- end }}
{{- end }}


{{/*
An "annotations:" block from chart.userAnnotations, or nothing when empty.
Takes the same arguments. Include with: {{- include ... | nindent 2 }}
*/}}
{{- define "chart.annotations" -}}
{{- $a := include "chart.userAnnotations" . | trim -}}
{{- if $a -}}
annotations:
  {{- $a | nindent 2 }}
{{- end -}}
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


{{/*
JOB_OVERRIDES JSON from controllerManager.job, or empty when nothing is set.
commonLabels are folded into labels and podLabels, and commonAnnotations into
annotations and podAnnotations; controllerManager.job wins on the same key.
The chart's own label keys and keys the operator manages (which it would
refuse at startup) are left out of the common maps, as are helm.sh/,
meta.helm.sh/ and kubectl.kubernetes.io/default-container annotations. Empty keys are
omitted, so an older operator that does not know a key is unaffected until it
is set. Unknown keys are passed through so the operator rejects a typo at
startup. Label, annotation and nodeSelector values are converted to strings; a
key with no value becomes "".
*/}}
{{- define "chart.jobOverrides" -}}
{{- $out := dict -}}
{{- $stringMaps := list "labels" "annotations" "podLabels" "podAnnotations" "nodeSelector" -}}
{{- $reserved := concat (include "chart.ownKeys" . | fromJsonArray) (list "log-watcher" "job-name" "controller-uid") -}}
{{- $reservedPrefixes := list "batch.kubernetes.io/" "integrations.jupiterone.io/" -}}
{{- $cl := dict -}}
{{- range $k, $v := (.Values.commonLabels | default dict) -}}
{{- $skip := has $k $reserved -}}
{{- range $reservedPrefixes -}}{{- if hasPrefix . $k -}}{{- $skip = true -}}{{- end -}}{{- end -}}
{{- if not $skip -}}{{- $_ := set $cl $k $v -}}{{- end -}}
{{- end -}}
{{- $ca := dict -}}
{{- range $k, $v := (.Values.commonAnnotations | default dict) -}}
{{- $skip := or (has $k $reserved) (eq $k "kubectl.kubernetes.io/default-container") (hasPrefix "helm.sh/" $k) (hasPrefix "meta.helm.sh/" $k) -}}
{{- range $reservedPrefixes -}}{{- if hasPrefix . $k -}}{{- $skip = true -}}{{- end -}}{{- end -}}
{{- if not $skip -}}{{- $_ := set $ca $k $v -}}{{- end -}}
{{- end -}}
{{- $fold := dict "labels" $cl "podLabels" $cl "annotations" $ca "podAnnotations" $ca -}}
{{- $job := (.Values.controllerManager.job | default dict) -}}
{{- range $key, $value := $job -}}
{{- if and $value (not (has $key $stringMaps)) -}}
{{- $_ := set $out $key $value -}}
{{- end -}}
{{- end -}}
{{- range $key := $stringMaps -}}
{{- $jv := get $job $key -}}
{{- if and $jv (not (kindIs "map" $jv)) -}}
{{- /* Not a map: pass it through for the operator to reject. */ -}}
{{- $_ := set $out $key $jv -}}
{{- else -}}
{{- $m := dict -}}
{{- range $k, $v := (get $fold $key | default dict) -}}
{{- $_ := set $m $k (ternary "" (toString $v) (kindIs "invalid" $v)) -}}
{{- end -}}
{{- range $k, $v := ($jv | default dict) -}}
{{- $_ := set $m $k (ternary "" (toString $v) (kindIs "invalid" $v)) -}}
{{- end -}}
{{- if $m -}}
{{- $_ := set $out $key $m -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- if $out -}}
{{- $out | toJson -}}
{{- end -}}
{{- end }}


{{/*
COMMON_LABELS JSON (commonLabels without the chart's own keys, values as
strings) for the operator's leader-election Lease, or empty.
*/}}
{{- define "chart.commonLabelsJson" -}}
{{- $own := include "chart.ownKeys" . | fromJsonArray -}}
{{- $m := dict -}}
{{- range $k, $v := (.Values.commonLabels | default dict) -}}
{{- if not (has $k $own) -}}
{{- $_ := set $m $k (ternary "" (toString $v) (kindIs "invalid" $v)) -}}
{{- end -}}
{{- end -}}
{{- if $m -}}
{{- $m | toJson -}}
{{- end -}}
{{- end }}
