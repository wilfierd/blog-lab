{{- define "blog-app.name" -}}
{{- .Chart.Name }}
{{- end }}

{{- define "blog-app.fullname" -}}
{{- .Release.Name }}-{{ .Chart.Name }}
{{- end }}

{{- define "blog-app.labels" -}}
app: {{ include "blog-app.name" . }}
release: {{ .Release.Name }}
{{- end }}

{{- define "blog-app.selectorLabels" -}}
app: {{ include "blog-app.name" . }}
{{- end }}
