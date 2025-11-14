#!/usr/bin/env bash

set -e

readonly NAMESPACE="${1}"

kubectl delete namespace "${NAMESPACE}"
