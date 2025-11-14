#!/usr/bin/env bash

set -e

NAMESPACE="${1}"
CLUSTER_NAME="${2}"
WAIT_FOR_CLUSTER_DELETION="${3:-false}"

kubectl --namespace "${NAMESPACE}" delete cluster "${CLUSTER_NAME}" --wait="${WAIT_FOR_CLUSTER_DELETION}"
