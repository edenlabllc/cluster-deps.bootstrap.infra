# CAPI v1.8.4 vs v1.12.9 — API / CRD review

Review document for comparing **Cluster API (core)** releases **v1.8.4** and **v1.12.9** (upstream tags in [kubernetes-sigs/cluster-api](https://github.com/kubernetes-sigs/cluster-api)).

**Audience:** platform / cluster lifecycle team evaluating a management-cluster upgrade together with [CAPA v2.8.2 → v2.12.1](capa-v2.8.2-vs-v2.12.1-review.md).

**Method:** OpenAPI schema diff of all `**/crd/bases/*.yaml` CRDs at stored version `v1beta1` (core CAPI CRD storage version in both tags). Field paths are CRD property paths.

**Headline:** Production CRD changes are **additive** — no fields removed on core kinds. One **new** production CRD: `MachineDrainRule`. Test-only CRDs (`InMemory*`) were replaced by `Dev*` in the test tree (ignore for production).

**Support note:** **v1.8.x is EOL** (since v1.11.0, Aug 2025). v1.12.x is in standard support. CAPA 2.12.x depends on CAPI **v1.12.8+** (`go.mod` in this repo).

---

## Summary table

| Area | v1.8.4 | v1.12.9 | Notes for us |
|------|--------|---------|--------------|
| Release support | EOL | Standard support | Security / bugfix reason to move |
| CRD kinds (prod) | 20 | 21 | +`MachineDrainRule` |
| Status model | `status.conditions` (v1beta1) | + `status.v1beta2.*` dual-write | **Apply CRDs before controllers** |
| Readiness / availability gates | — | Custom conditions for Ready/Available | Optional; useful for add-on gating |
| Drain control | Global controller flags | + per-rule `MachineDrainRule` | Fine-grained pod drain on scale/delete |
| Naming | Fixed patterns | + `*NamingStrategy` templates | Long cluster/machine names |
| ClusterClass topology | Same namespace only | + `classNamespace` | ClusterClass in another namespace |
| Kubeadm bootstrap | Standard cloud-init | + `bootCommands`, env-from-file | Self-managed CP only |
| MachinePool status | Basic | + `availableReplicas`, `upToDateReplicas` | Better rollout visibility |
| IPAM / addons | Present | + v1beta2 status on IPAddressClaim, CRS | Observability only |
| Pairing | CAPA ~2.8.x era | CAPA 2.12.x requires CAPI 1.12.x | Upgrade **together** |

---

## Why this comparison matters (with CAPA)

Your platform upgrade spans **two baselines**:

| Layer | From | To |
|-------|------|-----|
| CAPI core | v1.8.4 | v1.12.9 |
| CAPA | v2.8.2 | v2.12.1 (+ fork on v2.12.2) |

CAPI is the **management-cluster** contract (Cluster, Machine, MachinePool, …). CAPA is the **AWS infrastructure** provider. Both must move in lockstep: `clusterctl upgrade` bumps CAPI providers; CAPA image/CRDs must match the [contract version](https://cluster-api.sigs.k8s.io/reference/versions.html) CAPI 1.12 expects.

---

## New CRD kind

### `MachineDrainRule` (new in v1.12)

Fine-grained control over **how pods are drained** when machines are deleted or scaled down. Replaces one-size-fits-all drain with label-selected rules.

| Field | Example | Comment |
|-------|---------|---------|
| `spec.machines[].selector.matchLabels` | `cluster.x-k8s.io/cluster-name: prod` | Which Machines this rule applies to. |
| `spec.machines[].clusterSelector.matchLabels` | `environment: production` | Narrow by Cluster labels. |
| `spec.pods[].selector.matchLabels` | `app: database` | Which Pods get special drain handling. |
| `spec.pods[].namespaceSelector.matchLabels` | `team: platform` | Scope by namespace labels. |
| `spec.drain.behavior` | `WaitCompleted` | `Drain` (default), `Skip`, or `WaitCompleted`. |
| `spec.drain.order` | `100` | Higher order = drained later. |

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDrainRule
metadata:
  name: skip-system-pods
  namespace: capi-system
spec:
  machines:
    - selector:
        matchLabels:
          cluster.x-k8s.io/cluster-name: tenant-a
  pods:
    - selector:
        matchLabels:
          app: node-exporter
  drain:
    behavior: Skip
    order: 0
---
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachineDrainRule
metadata:
  name: drain-databases-last
spec:
  machines:
    - selector:
        matchLabels:
          cluster.x-k8s.io/cluster-name: tenant-a
  pods:
    - selector:
        matchLabels:
          app: postgres
  drain:
    behavior: Drain
    order: 100
```

**Useful for us:** Safer node drains during MachinePool / MNG rollouts; skip DaemonSets or drain stateful pods last.

---

## Cross-cutting theme: `status.v1beta2`

Almost every core kind gained a **`status.v1beta2`** block. Controllers in v1.10+ **dual-write**:

- Legacy `status.conditions` (v1beta1 shape) — still present.
- New `status.v1beta2.conditions` — richer contract (includes `observedGeneration` per condition).

**Also under v1beta2 (where applicable):**

| Field | Example | Comment |
|-------|---------|---------|
| `status.v1beta2.conditions[].type` | `Ready` | Standard CAPI condition types. |
| `status.v1beta2.conditions[].status` | `True` | `True` / `False` / `Unknown`. |
| `status.v1beta2.conditions[].observedGeneration` | `3` | Ties condition to spec generation. |
| `status.v1beta2.*Replicas` | `5` | Aggregated replica counts (Cluster, MachinePool, KCP). |

**Upgrade impact:** If management-cluster CRDs stay at v1.8.4 while controllers run v1.12.9, controllers write unknown fields → reconciliation warnings (same class of issue as CAPA `observedGeneration`).

**Action:** Apply CAPI CRDs from v1.12.9 **before** rolling controller Deployments.

---

## Per-resource review

### `Cluster` (+30 fields)

Central object linking control plane + workers. Most relevant for **ClusterClass / topology** users.

#### Spec — gates and topology

| Field | Example | Comment |
|-------|---------|---------|
| `spec.availabilityGates[].conditionType` | `MyAddonReady` | Extra condition before Cluster becomes Available. |
| `spec.availabilityGates[].polarity` | `Positive` | `Positive` = must be True; `Negative` = must be False. |
| `spec.topology.classNamespace` | `clusterclass-system` | Use ClusterClass from another namespace. |
| `spec.topology.controlPlane.readinessGates[]` | (same shape) | Gate Machine Ready for control plane Machines. |
| `spec.topology.workers.machineDeployments[].readinessGates[]` | (same shape) | Gate Ready per worker MachineDeployment in topology. |

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod
  namespace: team-a
spec:
  topology:
    class: eks-standard
    classNamespace: platform-classes   # ClusterClass lives elsewhere
    version: v1.31.0
  availabilityGates:
    - conditionType: CNIReady
      polarity: Positive
```

#### Status — v1beta2 aggregates

| Field | Example | Comment |
|-------|---------|---------|
| `status.v1beta2.controlPlane.replicas` | `3` | Total CP machines. |
| `status.v1beta2.controlPlane.readyReplicas` | `3` | CP machines with Node Ready. |
| `status.v1beta2.controlPlane.availableReplicas` | `3` | CP machines passing readiness gates. |
| `status.v1beta2.controlPlane.upToDateReplicas` | `2` | CP machines on current revision (rolling upgrade). |
| `status.v1beta2.workers.*` | (same fields) | Worker pool aggregates across all MDs/MPs. |

**Useful for us:** `classNamespace` if platform team owns ClusterClasses centrally; availability gates if tenants wait on CNI / ingress before marking cluster Available.

---

### `ClusterClass` (+29 fields)

Template for topology-based clusters.

| Field | Example | Comment |
|-------|---------|---------|
| `spec.availabilityGates[]` | (see Cluster) | Default gates for clusters using this class. |
| `spec.controlPlane.readinessGates[]` | (see Cluster) | Default CP machine gates. |
| `spec.workers.machineDeployments[].readinessGates[]` | (see Cluster) | Per-pool worker gates. |
| `spec.infrastructureNamingStrategy.template` | `{{ .cluster.name }}-infra` | Pattern for infra object names (length limits). |
| `spec.variables[].schema.openAPIV3Schema.oneOf` | (JSON schema) | Richer variable validation in templates. |

```yaml
spec:
  infrastructureNamingStrategy:
    template: "{{ .cluster.name }}-{{ .random }}"
  controlPlane:
    readinessGates:
      - conditionType: APIServerHealthy
        polarity: Positive
```

**Useful for us:** Standardize EKS / CAPA ClusterClass defaults; naming strategy if AWS object name limits bite.

---

### `Machine` (+16 fields)

Single node lifecycle object (maps to EC2 instance or EKS node indirectly via infra provider).

| Field | Example | Comment |
|-------|---------|---------|
| `spec.readinessGates[].conditionType` | `GPUDriverInstalled` | Machine not Ready until custom condition True. |
| `spec.readinessGates[].polarity` | `Positive` | Gate polarity. |
| `status.deletion.nodeDrainStartTime` | `2026-03-15T10:00:00Z` | When cordon/drain started (debug stuck deletes). |
| `status.deletion.waitForNodeVolumeDetachStartTime` | `2026-03-15T10:05:00Z` | Volume detach phase timing. |
| `status.nodeInfo.swap.capacity` | `8Gi` | Node swap capacity reporting. |
| `status.v1beta2.conditions[]` | (standard) | New conditions contract. |

```yaml
spec:
  readinessGates:
    - conditionType: CustomBootstrapComplete
      polarity: Positive
```

**Useful for us:** EKS MNG / MachinePool nodes still surface as Machines — readiness gates help gate MD rollouts on post-bootstrap hooks.

---

### `MachineDeployment` (+16 fields)

Rolling worker pool (non-EKS or self-managed workers).

| Field | Example | Comment |
|-------|---------|---------|
| `spec.machineNamingStrategy.template` | `{{ .machineDeployment.name }}-{{ .random }}` | Custom Machine object names. |
| `spec.template.spec.readinessGates[]` | (see Machine) | Gates for Machines created by this MD. |
| `status.v1beta2.*Replicas` | (same as Cluster workers) | Rollout visibility. |

**Useful for us:** Low priority if EKS MNG / MachinePool only; relevant for EC2 worker MDs.

---

### `MachineSet` (+16 fields)

Same additions as MachineDeployment (`machineNamingStrategy`, `readinessGates`, `status.v1beta2`).

---

### `MachinePool` (+14 fields)

**High relevance** — CAPA `AWSMachinePool` and EKS `AWSManagedMachinePool` integrate here.

| Field | Example | Comment |
|-------|---------|---------|
| `spec.template.spec.readinessGates[]` | (see Machine) | Gate pool Machines before counting Ready. |
| `status.v1beta2.readyReplicas` | `10` | Ready machines in pool. |
| `status.v1beta2.availableReplicas` | `10` | Ready + passed readiness gates. |
| `status.v1beta2.upToDateReplicas` | `8` | Machines on current template revision. |
| `status.v1beta2.conditions[]` | `type: Ready` | Pool-level readiness. |

```yaml
apiVersion: cluster.x-k8s.io/v1beta1
kind: MachinePool
metadata:
  name: workers
spec:
  clusterName: prod
  replicas: 10
  template:
    spec:
      readinessGates:
        - conditionType: NodeRegistrationComplete
          polarity: Positive
```

**Useful for us:** Better status for tenant MachinePools; combine with CAPA MNG ASG tag fix for correct node labels.

---

### `MachineHealthCheck` (+8 fields)

| Field | Example | Comment |
|-------|---------|---------|
| `status.v1beta2.conditions[]` | `type: RemediationAllowed` | New status contract only — **no spec changes**. |

Spec (`nodeStartupTimeout`, `unhealthyConditions`, etc.) unchanged between v1.8.4 and v1.12.9.

---

### `KubeadmControlPlane` (+37 fields)

Self-managed **kubeadm** control plane (not EKS). Skip if EKS-only.

| Field | Example | Comment |
|-------|---------|---------|
| `spec.machineNamingStrategy.template` | `{{ .cluster.name }}-cp-{{ .ordinal }}` | CP Machine naming. |
| `spec.machineTemplate.readinessGates[]` | (see Machine) | CP machine gates. |
| `spec.kubeadmConfigSpec.bootCommands` | `["echo opts >> /etc/default/grub"]` | Early cloud-init commands before kubeadm. |
| `spec.kubeadmConfigSpec.clusterConfiguration.apiServer.extraEnvs[].valueFrom.fileKeyRef` | volume/path/key | Load apiserver env from file (EnvFiles gate). |
| `status.v1beta2.readyReplicas` | `3` | CP rollout status. |
| `status.v1beta2.upToDateReplicas` | `2` | CP machines on current revision. |

```yaml
spec:
  kubeadmConfigSpec:
    bootCommands:
      - swapoff -a
    clusterConfiguration:
      apiServer:
        extraEnvs:
          - name: FEATURE_X
            valueFrom:
              fileKeyRef:
                volumeName: env-config
                path: apiserver.env
                key: FEATURE_X
```

---

### `KubeadmConfig` (+29 fields)

Bootstrap config for kubeadm nodes. Same `bootCommands` and `extraEnvs[].valueFrom.fileKeyRef` additions as KCP. **Not used for EKS** (`EKSConfig` unchanged — 0 field delta).

---

### `ClusterResourceSet` (+8 fields)

Automated application of ConfigMaps/Secrets to matching clusters.

| Field | Example | Comment |
|-------|---------|---------|
| `status.v1beta2.conditions[]` | `type: ResourcesApplied` | v1beta2 status only. |

Spec unchanged.

---

### `ExtensionConfig` (+8 fields)

Runtime extension / webhook configuration for CAPI lifecycle hooks.

| Field | Example | Comment |
|-------|---------|---------|
| `status.v1beta2.conditions[]` | `type: HandshakeCompleted` | v1beta2 status only. |

---

### `IPAddress` / `IPAddressClaim` (+8 on Claim)

IPAM integration for clusters using IPAM provider.

| Field | Example | Comment |
|-------|---------|---------|
| `status.v1beta2.conditions[]` | (standard) | v1beta2 status on Claim only; IPAddress unchanged. |

**Useful for us:** Only if IPAM provider is deployed.

---

### Unchanged production CRDs (0 field delta)

| Kind | Comment |
|------|---------|
| `ClusterResourceSetBinding` | No schema change |
| `Metadata` / `Provider` (clusterctl) | No schema change |
| `IPAddress` | No schema change |

---

## Thematic grouping (what might matter most)

### High priority (management cluster upgrade)

| Feature | Resource | Why |
|---------|----------|-----|
| `status.v1beta2` everywhere | All core kinds | CRD + controller alignment; avoids unknown-field errors |
| CAPI 1.12 + CAPA 2.12 pairing | Platform | Contract version match |
| `MachinePool` v1beta2 status | MachinePool | Rollout visibility for AWS MNG / MP |
| EOL exit v1.8 | Platform | No patches on 1.8.x |

### Medium priority

| Feature | Resource | Why |
|---------|----------|-----|
| `MachineDrainRule` | New CRD | Controlled drains during upgrades |
| Readiness / availability gates | Cluster, Machine*, Class | Gate clusters on CNI / custom hooks |
| `topology.classNamespace` | Cluster | Central ClusterClass management |
| Naming strategies | ClusterClass, MD, KCP | AWS name length / conventions |

### Low priority (EKS-focused platform)

| Feature | Resource | Why |
|---------|----------|-----|
| Kubeadm bootCommands / env files | KCP, KubeadmConfig | Self-managed only |
| IPAddressClaim v1beta2 | IPAM | Only with IPAM provider |
| Docker provider deltas | Dev/Docker test CRDs | Not production |

---

## Upgrade path notes

### Version stepping

CAPI recommends upgrading **one minor at a time** via `clusterctl upgrade` (e.g. 1.8 → 1.9 → … → 1.12), or follow your vendor runbook. Skipping minors may work but is less tested.

### Order of operations

1. Backup management cluster etcd / YAML.
2. Apply **CAPI CRDs** for target version.
3. Apply **CAPA CRDs** for target version (see [CAPA review doc](capa-v2.8.2-vs-v2.12.1-review.md)).
4. `clusterctl upgrade apply` (core + bootstrap + control-plane providers).
5. Upgrade **CAPA** controller Deployment image.
6. Verify `Cluster`, `MachinePool`, `AWSManagedControlPlane` conditions.

### Kubernetes version support (management cluster)

CAPI **v1.12.9** core provider supports management cluster Kubernetes **v1.29 – v1.35** (see [versions.md](https://github.com/kubernetes-sigs/cluster-api/blob/v1.12.9/docs/book/src/reference/versions.md)). Confirm your management cluster K8s version is in matrix before upgrading.

### EKS workload clusters

For EKS tenants you primarily touch:

- `Cluster` (topology / class refs)
- `MachinePool` + CAPA `AWSManagedMachinePool`
- Possibly `MachineHealthCheck`

You typically **do not** use `KubeadmControlPlane` / `KubeadmConfig` on EKS.

---

## Appendix A — Full field addition counts (production CRDs)

| Kind | +fields | −fields | Notes |
|------|---------|---------|-------|
| Cluster | 30 | 0 | |
| ClusterClass | 29 | 0 | |
| KubeadmControlPlane | 37 | 0 | |
| KubeadmConfig | 29 | 0 | |
| KubeadmConfigTemplate | 21 | 0 | |
| KubeadmControlPlaneTemplate | 23 | 0 | |
| Machine | 16 | 0 | |
| MachineDeployment | 16 | 0 | |
| MachineSet | 16 | 0 | |
| MachinePool | 14 | 0 | |
| MachineHealthCheck | 8 | 0 | status only |
| ClusterResourceSet | 8 | 0 | status only |
| ExtensionConfig | 8 | 0 | status only |
| IPAddressClaim | 8 | 0 | status only |
| MachineDrainRule | 33 | 0 | **new kind** |
| ClusterResourceSetBinding | 0 | 0 | |
| IPAddress | 0 | 0 | |
| Metadata / Provider | 0 | 0 | |

---

## Appendix B — Combined upgrade checklist (CAPI + CAPA)

Use with [CAPA checklist](capa-v2.8.2-vs-v2.12.1-review.md#appendix-c--suggested-review-checklist-for-expert-session).

1. **Baseline:** Document current CAPI (`v1.8.4`) and CAPA (`v2.8.2`) on management cluster.
2. **Target:** CAPI `v1.12.9` + CAPA `v2.12.1` (fork `v2.12.2` image).
3. **CRDs:** Apply both CAPI and CAPA CRD sets before controllers.
4. **Contract:** Confirm CAPA release notes require CAPI 1.12.x.
5. **EKS auth:** Evaluate CAPA `accessEntries` vs staying on `aws-auth`.
6. **Drain:** Evaluate new `MachineDrainRule` vs default drain behavior.
7. **Fork patches:** Keep ASG tag fix + optional `singleNatGateway` on fork image.
8. **Tenant impact:** Existing workload clusters — rolling vs recreate for flag changes?
9. **Rollback:** Pin previous controller images + CRD backup.

---

## References

- CAPI tags: `v1.8.4` … `v1.12.9` in [kubernetes-sigs/cluster-api](https://github.com/kubernetes-sigs/cluster-api)
- [CAPI version support matrix](https://cluster-api.sigs.k8s.io/reference/versions.html)
- [MachineDrainRule proposal](https://github.com/kubernetes-sigs/cluster-api/tree/main/docs/proposals)
- [CAPA v2.8.2 vs v2.12.1 review](capa-v2.8.2-vs-v2.12.1-review.md) (companion doc in this repo)

*Generated from CRD OpenAPI diff between git tags `v1.8.4` and `v1.12.9` in a local clone of kubernetes-sigs/cluster-api.*
