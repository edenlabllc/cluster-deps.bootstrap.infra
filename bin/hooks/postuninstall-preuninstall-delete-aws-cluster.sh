#!/usr/bin/env bash

set -e

NAMESPACE="${1}"
RELEASE_NAME="${2}"
WAIT_FOR_CLUSTER_DELETION="${3:-false}"

kubectl --namespace "${NAMESPACE}" delete cluster "${RELEASE_NAME}" --wait="${WAIT_FOR_CLUSTER_DELETION}"
