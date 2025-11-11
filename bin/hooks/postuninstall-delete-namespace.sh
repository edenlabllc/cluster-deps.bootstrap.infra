#!/usr/bin/env bash

set -e

NAMESPACE="${1}"

kubectl delete namespace "${NAMESPACE}"
