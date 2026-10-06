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
A label or annotation value as a string; a key with no value (null) becomes "".
*/}}
{{- define "chart.str" -}}
{{- if not (kindIs "invalid" .) }}{{ toString . }}{{ end -}}
{{- end }}


{{/*
commonLabels (or with "annotation", commonAnnotations) as a JSON object of
string values, without the keys left out everywhere: the chart's own label
keys, and helm.sh/, meta.helm.sh/ and kubectl.kubernetes.io/default-container
annotations (Helm acts on the first two; the chart sets the last on the manager
pod). With "run", keys the operator manages on run objects are also left out,
and the chart's own label keys from annotations too: the operator refuses them
in JOB_OVERRIDES. Always a JSON object. Takes (dict "ctx" $ "annotation" bool
"run" bool).
*/}}
{{- define "chart.commonMap" -}}
{{- $own := include "chart.ownKeys" .ctx | fromJsonArray -}}
{{- $annotation := .annotation | default false -}}
{{- $run := .run | default false -}}
{{- $source := ternary .ctx.Values.commonAnnotations .ctx.Values.commonLabels $annotation | default dict -}}
{{- $out := dict -}}
{{- range $k, $v := $source -}}
{{- $skip := and (not $annotation) (has $k $own) -}}
{{- if and $annotation (or (hasPrefix "helm.sh/" $k) (hasPrefix "meta.helm.sh/" $k) (eq $k "kubectl.kubernetes.io/default-container")) -}}
{{- $skip = true -}}
{{- end -}}
{{- if and $run (or (has $k $own) (has $k (list "log-watcher" "job-name" "controller-uid")) (hasPrefix "batch.kubernetes.io/" $k) (hasPrefix "integrations.jupiterone.io/" $k)) -}}
{{- $skip = true -}}
{{- end -}}
{{- if not $skip -}}
{{- $_ := set $out $k (include "chart.str" $v) -}}
{{- end -}}
{{- end -}}
{{- $out | toJson -}}
{{- end }}


{{/*
User labels: commonLabels overlaid by the optional "specific" map (for
example controllerManager.pod.labels), one quoted "key: value" per line, each
line starting with a newline. The chart's own label keys are skipped from both
maps. Takes (dict "ctx" $ "specific" map).
*/}}
{{- define "chart.userLabels" -}}
{{- $own := include "chart.ownKeys" .ctx | fromJsonArray -}}
{{- $m := include "chart.commonMap" (dict "ctx" .ctx) | fromJson -}}
{{- range $k, $v := (.specific | default dict) -}}
{{- $_ := set $m $k (include "chart.str" $v) -}}
{{- end -}}
{{- range $k, $v := $m }}
{{- if not (has $k $own) }}
{{ $k | quote }}: {{ $v | quote }}
{{- end }}
{{- end }}
{{- end }}


{{/*
User annotations: commonAnnotations overlaid by the optional "specific" map,
in the same format as chart.userLabels. kubectl.kubernetes.io/default-container
is skipped from both maps, and "skipPrefix" drops keys with that prefix from
both. Takes (dict "ctx" $ "specific" map "skipPrefix" s).
*/}}
{{- define "chart.userAnnotations" -}}
{{- $skipPrefix := .skipPrefix -}}
{{- $m := include "chart.commonMap" (dict "ctx" .ctx "annotation" true) | fromJson -}}
{{- range $k, $v := (.specific | default dict) -}}
{{- $_ := set $m $k (include "chart.str" $v) -}}
{{- end -}}
{{- range $k, $v := $m }}
{{- if not (or (eq $k "kubectl.kubernetes.io/default-container") (and $skipPrefix (hasPrefix $skipPrefix $k))) }}
{{ $k | quote }}: {{ $v | quote }}
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
{{- $cl := include "chart.commonMap" (dict "ctx" . "run" true) | fromJson -}}
{{- $ca := include "chart.commonMap" (dict "ctx" . "annotation" true "run" true) | fromJson -}}
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
{{- $_ := set $m $k $v -}}
{{- end -}}
{{- range $k, $v := ($jv | default dict) -}}
{{- $_ := set $m $k (include "chart.str" $v) -}}
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
{{- $m := include "chart.commonMap" (dict "ctx" .) | fromJson -}}
{{- if $m -}}
{{- $m | toJson -}}
{{- end -}}
{{- end }}
