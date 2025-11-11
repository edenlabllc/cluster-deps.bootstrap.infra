#!/usr/bin/env bash

set -e

NAMESPACE="${1}"
RELEASE_NAME="${2}"
LIMIT="${3:-120}"

GO_TEMPLATE='
  {{- range .items -}}
    {{- if not .status }}0{{- end }}
    {{- if ne .status.phase "Provisioned" }}0{{- end }}
  {{- end -}}
'

COUNT=1
while true; do
  STATUS="$(kubectl --namespace "${NAMESPACE}" get awsiamprovision \
    --selector "app.kubernetes.io/instance=${RELEASE_NAME}" \
    --output "go-template=${GO_TEMPLATE}")"
  if [[ "${STATUS}" != "" && "${COUNT}" -le "${LIMIT}" ]]; then
    sleep 1
    (( ++COUNT ))
  elif [[ "${COUNT}" -gt "${LIMIT}" ]]; then
    >&2 echo "Limit exceeded."
    exit 1
  else
    echo
    kubectl --namespace "${NAMESPACE}" get awsiamprovision --selector "app.kubernetes.io/instance=${RELEASE_NAME}"
    break
  fi
done
