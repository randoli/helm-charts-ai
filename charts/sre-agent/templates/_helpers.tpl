{{/*
Application name used in the standard labels. Overridable via nameOverride.
*/}}
{{- define "sre-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chartName" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Selector labels shared by the Deployment's matchLabels, its pod template and
the Service selector. These are immutable on a live Deployment — never add or
remove keys without a migration plan.
*/}}
{{- define "selectorLabels" -}}
app: randoli-sre-agent
{{- end -}}

{{/*
Standard labels applied to every resource rendered by this chart.
The managed-by / helm.sh/chart pair is suppressed when the chart is rendered
by something other than Helm (creator != "helm").
*/}}
{{- define "labels" -}}
app.kubernetes.io/name: {{ include "sre-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: sre-agent
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- if eq (default "helm" .Values.creator) "helm" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ include "chartName" . }}
{{- end -}}
{{- end -}}
