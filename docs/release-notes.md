# Deps Release Notes

## Release v0.3.0

## What's new
- Bumped `tenant-artifact` GitHub Action to `v2` for tenant release with the new RMK version.

## Bug fixes

## Additional information

### Mandatory updates for `project.yaml`

### List of updated releases

### List of added releases

---

## Release v0.2.0

## What's new
- Added example K3D cluster configuration values.
- Updated `GCP GKE` control plane version to `v1.30.8`.
- Changed the sequence of launching releases for `aws-iam-config`.
- Updated charts for releases: `aws-iam-config`, `aws-iam-controller`.

## Bug fixes

## Additional information

### Mandatory updates for `project.yaml`

### List of updated releases
```yaml
  - name: aws-iam-config
    chart: core-charts/aws-iam-config
    version: 0.2.0
  - name: aws-iam-controller
    chart: core-charts/iam-chart
    version: 1.3.15
```

### List of added releases

---

## Release v0.1.0

## What's new
- Prepared repository for OSS.
- Added project structure files.

## Bug fixes

## Additional information

### Mandatory updates for `project.yaml`

### List of updated releases

### List of added releases
```yaml
  - name: capi-cluster
    chart: core-charts/k3d-cluster
    version: 0.1.0
  - name: clusterctl-config
    chart: core-charts/clusterctl-config
    version: 0.1.2
  - name: k3d-cluster
    chart: core-charts/k3d-cluster
    version: 0.1.0
  - name: aws-iam-controller
    chart: core-charts/iam-chart
    version: 1.3.13
  - name: aws-iam-provision-operator
    chart: core-charts/app
    version: 1.6.0
  - name: aws-iam-config
    chart: core-charts/aws-iam-config
    version: 0.1.0
  - name: aws-cluster
    chart: core-charts/aws-cluster
    version: 0.2.1
  - name: aws-iam-provision
    chart: core-charts/aws-iam-provision
    version: 0.1.0
  - name: azure-cluster
    chart: core-charts/azure-cluster
    version: 0.2.3
  - name: gcp-cluster
    chart: core-charts/gcp-cluster
    version: 0.2.1
```