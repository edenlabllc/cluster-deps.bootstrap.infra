# Cluster Deps Release Notes

## Release v0.3.3

## What's new
- Bumped `helmfile.hooks.infra` version to `v1.30.1`.
- Added auto update `deps.bootstrap.infra` tenant to `tenant-artifact` GitHub Action.

## Bug fixes

## Additional information

### Mandatory updates for `project.yaml`
```yaml
inventory:
  hooks:
    helmfile.hooks.infra:
      version: v1.30.1
```

### List of updated releases

### List of added releases

---

## Release v0.3.2

## What's new

## Bug fixes
- Bump the `aws-iam-provision` release's chart version to `0.2.1` to handle null items correctly in the template ranges.

## Additional information

### Mandatory updates for `project.yaml`

### List of updated releases
```yaml
  - name: aws-iam-provision
    chart: core-charts/aws-iam-provision
    version: 0.2.1
```

### List of added releases

---

## Release v0.3.1

## What's new
- Bumped `helmfile.hooks.infra` version to `v1.30.0`.

## Bug fixes

## Additional information

### Mandatory updates for `project.yaml`
```yaml
inventory:
  hooks:
    helmfile.hooks.infra:
      version: v1.30.0
```

### List of updated releases

### List of added releases

---

## Release v0.3.0

## What's new
- Added role and policy for `ebs-snapshot-provision-operator`.
- Bumped `tenant-artifact` GitHub Action to `v2` for tenant repositories which use the new `v0.45.0` RMK version.
- Bumped `kubectl` version to `v1.30.10` for proper support of Kubernetes `v1.30.X`.
- Removed the `aws-iam-config`, `aws-iam-controller` releases for redundancy.
- Updated configuration for the `aws-iam-provision` release to support the new version of `aws-iam-provision-operator`.
- Updated control plane version for all cluster providers.
- Upgraded `aws-iam-provision-operator` to `v0.3.0` to support IAM role and policy management.

## Bug fixes

## Additional information

### Mandatory updates for `project.yaml`
```yaml
inventory:
  hooks:
    helmfile.hooks.infra:
      version: v1.29.2
  tools:
    kubectl:
      version: 1.30.10
    k3d:
      version: 5.8.3
```

### List of updated releases
```yaml
  - name: aws-iam-provision
    chart: core-charts/aws-iam-provision
    version: 0.2.0
  - name: aws-iam-provision-operator
    chart: core-charts/app
    version: 2.1.0
  - name: capi-cluster
    chart: core-charts/k3d-cluster
    version: 0.2.0
  - name: k3d-cluster
    chart: core-charts/k3d-cluster
    version: 0.2.0
```

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
