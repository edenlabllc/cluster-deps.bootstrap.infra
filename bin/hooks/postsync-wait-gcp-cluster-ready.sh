#!/usr/bin/env bash

set -e

readonly NAMESPACE="${1}"
readonly RELEASE_NAME="${2}"
readonly LIMIT="${3:-1200}"

# CAPI v1beta2: Cluster/MachinePool use status.initialization.*
# GCP managed provider CRs still expose status.ready / status.initialized.
readonly GO_TEMPLATE='
  {{- range .items -}}
    {{- if eq .kind "Cluster" -}}
      {{- if ne .status.phase "Provisioned" }}0{{- end }}
      {{- if not .status.initialization.controlPlaneInitialized }}0{{- end }}
      {{- if not .status.initialization.infrastructureProvisioned }}0{{- end }}
    {{- end -}}
    {{- if eq .kind "GCPManagedCluster" -}}
      {{- if not .status.ready }}0{{- end }}
    {{- end -}}
    {{- if eq .kind "GCPManagedControlPlane" -}}
      {{- if not .status.ready }}0{{- end }}
      {{- if not .status.initialized }}0{{- end }}
    {{- end -}}
    {{- if eq .kind "GCPManagedMachinePool" -}}
      {{- if not .status.ready }}0{{- end -}}
    {{- end -}}
    {{- if eq .kind "MachinePool" -}}
      {{- if ne .status.phase "Running" }}0{{- end }}
      {{- if not .status.initialization.bootstrapDataSecretCreated }}0{{- end }}
      {{- if not .status.initialization.infrastructureProvisioned }}0{{- end }}
    {{- end -}}
  {{- end -}}
'

COUNT=1
while true; do
  STATUS="$(kubectl --namespace "${NAMESPACE}" get cluster-api \
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
    kubectl --namespace "${NAMESPACE}" get cluster-api --selector "app.kubernetes.io/instance=${RELEASE_NAME}"
    break
  fi
done
