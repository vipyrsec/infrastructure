{{/* Generate container image properties */}}
{{- define "vipyrsec.image" -}}
image: {{ printf "%s/%s:%s" .registry .repository .tag }}
imagePullPolicy: {{ .pullPolicy }}
{{- end -}}
