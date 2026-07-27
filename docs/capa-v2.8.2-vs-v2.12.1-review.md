# CAPA v2.8.2 vs v2.12.1 — API / CRD review

Review document for comparing **Cluster API Provider AWS (CAPA)** releases **v2.8.2** and **v2.12.1** (upstream tags in this repository).

**Audience:** platform / cluster lifecycle team evaluating an upgrade path and new capabilities.

**Method:** OpenAPI schema diff of `config/crd/bases/*.yaml` at `v1beta2` between git tags `v2.8.2` and `v2.12.1`. Field paths are CRD property paths (e.g. `spec.accessEntries[].principalARN`).

**Headline:** All changes on **existing** CRD kinds are **additive** — no fields were removed. Seven **new** CRD kinds appear in v2.12.1.

---

## Summary table

| Area | v2.8.2 | v2.12.1 | Notes for us |
|------|--------|---------|--------------|
| CRD kinds | 17 | 24 | +7 new kinds (Nodeadm, templates, ROSA helpers) |
| EKS auth | `aws-auth` ConfigMap only | + EKS Access API (`accessConfig`, `accessEntries`) | Plan migration off `aws-auth` if adopting |
| EKS node groups | — | `nodeRepairConfig`, `lifecycleHooks` | Auto-repair, ASG hooks |
| Network / LB | IPv4-focused | IPv6 ELB/target groups, DNS resolution check | Dual-stack clusters |
| EC2 instances | Basic launch template | Nitro Enclaves, dedicated hosts, IPv6 primary, nested virt | Mostly optional |
| ROSA | Early / limited | FIPS, channels, log forwarders, role configs | Only if using ROSA |
| Bootstrap | `EKSConfig` only | + `NodeadmConfig` (self-managed K8s) | New bootstrap path |
| Controller status | — | `status.observedGeneration` on MCP | **Must apply CRDs** before controller upgrade |

---

## New CRD kinds (not in v2.8.2)

| Kind | API group | Purpose |
|------|-----------|---------|
| `NodeadmConfig` / `NodeadmConfigTemplate` | `bootstrap.cluster.x-k8s.io` | Bootstrap for self-managed clusters via [nodeadm](https://github.com/kubernetes-sigs/cluster-api-provider-aws/blob/main/docs/proposal/20250922-nodeadm-bootstrap.md) |
| `AWSManagedControlPlaneTemplate` | `controlplane.cluster.x-k8s.io` | ClusterClass-style template for EKS control planes |
| `AWSManagedClusterTemplate` | `infrastructure.cluster.x-k8s.io` | Template wrapper for managed cluster infra |
| `ROSANetwork` | `infrastructure.cluster.x-k8s.io` | ROSA network configuration object |
| `ROSAOCMRoleConfig` / `ROSARoleConfig` | `infrastructure.cluster.x-k8s.io` | ROSA IAM / OCM role setup helpers |

**Unchanged (0 field delta):** `AWSClusterControllerIdentity`, `AWSClusterRoleIdentity`, `AWSClusterStaticIdentity`, `AWSManagedCluster`, `EKSConfig`, `EKSConfigTemplate`, `ROSACluster`.

---

## Upgrade prerequisites

1. **Apply CRDs before the controller** — v2.12 controllers write `status.observedGeneration` and other new status fields. Old CRDs cause `unknown field` errors and stuck reconciliation.
2. **CAPI core version** — CAPA 2.12 targets newer Cluster API; align `cluster-api`, `cluster-api-provider-aws`, and bootstrap/control-plane provider versions per [CAPA release notes](https://github.com/kubernetes-sigs/cluster-api-provider-aws/releases).
3. **EKS Access API** — if you use `accessEntries`, set `authenticationMode` to `api` or `api_and_config_map`; `config_map` alone is insufficient for access entries.
4. **No automatic NAT migration** — network layout flags (including any fork-specific `singleNatGateway`) do not reshape existing NAT gateways; plan VPC changes explicitly.

---

## Per-resource review

### `AWSManagedControlPlane` (+48 fields)

Primary resource for **EKS managed control planes**. Highest impact for typical EKS deployments.

#### EKS Access API (new in 2.12)

Replaces / complements the legacy `aws-auth` ConfigMap for IAM → Kubernetes RBAC mapping.

| Field | Example | Comment |
|-------|---------|---------|
| `spec.accessConfig.authenticationMode` | `api_and_config_map` | `config_map` (default) = v2.8 behavior. Use `api` or `api_and_config_map` to enable access entries. |
| `spec.accessConfig.bootstrapClusterCreatorAdminPermissions` | `true` | Grants admin to cluster creator IAM principal at create time only. |
| `spec.accessEntries[].principalARN` | `arn:aws:iam::123456789012:role/PlatformAdmin` | IAM role/user ARN to grant cluster access. |
| `spec.accessEntries[].type` | `standard` | `standard`, `ec2_linux`, `ec2_windows`, etc. Node roles often use `ec2_linux`. |
| `spec.accessEntries[].kubernetesGroups` | `["cluster-admins"]` | K8s groups for `standard` entries; not with `ec2_linux` / `ec2_windows`. |
| `spec.accessEntries[].accessPolicies[].policyARN` | `arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy` | AWS-managed EKS access policy ARN. |
| `spec.accessEntries[].accessPolicies[].accessScope.type` | `cluster` | `cluster` or `namespace`. |
| `spec.accessEntries[].accessPolicies[].accessScope.namespaces` | `["team-a", "team-b"]` | Required when scope is `namespace`. |

```yaml
spec:
  accessConfig:
    authenticationMode: api_and_config_map
    bootstrapClusterCreatorAdminPermissions: true
  accessEntries:
    - principalARN: arn:aws:iam::123456789012:role/PlatformAdmin
      type: standard
      accessPolicies:
        - policyARN: arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
          accessScope:
            type: cluster
    - principalARN: arn:aws:iam::123456789012:role/EKSNodeRole
      type: ec2_linux
```

**Useful for us:** Central IAM-based access without editing `aws-auth`; aligns with AWS direction. Requires auth mode change and testing with existing SSO / IRSA flows.

#### Cluster lifecycle & IAM

| Field | Example | Comment |
|-------|---------|---------|
| `spec.upgradePolicy` | `standard` | `extended` = pay for extended K8s support; `standard` = auto-upgrade at end of standard support. AWS default for new clusters is often `extended`. |
| `spec.rolePath` | `/custom/` | IAM path for cluster / node IAM roles. |
| `spec.rolePermissionsBoundary` | `arn:aws:iam::123456789012:policy/PermissionsBoundary` | Permissions boundary on created roles. |
| `spec.addons[].preserveOnDelete` | `true` | Keep EKS addon in AWS when removed from spec (no EKS delete call). |

```yaml
spec:
  upgradePolicy: standard
  rolePath: /platform/
  rolePermissionsBoundary: arn:aws:iam::123456789012:policy/CAPAPermissionsBoundary
  addons:
    - name: vpc-cni
      version: v1.18.0-eksbuild.1
      preserveOnDelete: true
```

#### Network — extra node security group rules

| Field | Example | Comment |
|-------|---------|---------|
| `spec.network.additionalNodeIngressRules[].protocol` | `tcp` | Also `-1` (all), `udp`, `icmp`, etc. |
| `spec.network.additionalNodeIngressRules[].fromPort` / `toPort` | `443` / `443` | Port range on worker node SG. |
| `spec.network.additionalNodeIngressRules[].cidrBlocks` | `["10.0.0.0/8"]` | Mutually exclusive with `sourceSecurityGroupIds` / `sourceSecurityGroupRoles`. |
| `spec.network.additionalNodeIngressRules[].sourceSecurityGroupRoles` | `["bastion"]` | Reference CAPA SG roles instead of raw IDs. |
| `spec.network.additionalNodeIngressRules[].natGatewaysIPsSource` | `true` | Use NAT gateway public IPs as rule source (dynamic egress allow-list). |

```yaml
spec:
  network:
    additionalNodeIngressRules:
      - description: Allow bastion SSH to nodes
        protocol: tcp
        fromPort: 22
        toPort: 22
        sourceSecurityGroupRoles:
          - bastion
      - description: Allow office egress via NAT
        protocol: tcp
        fromPort: 443
        toPort: 443
        natGatewaysIPsSource: true
```

**Useful for us:** Bastion / VPN access to nodes without hand-editing SGs; NAT-based allow lists for external webhooks hitting nodes.

#### VPC CNI env from files

| Field | Example | Comment |
|-------|---------|---------|
| `spec.vpcCni.env[].valueFrom.fileKeyRef.volumeName` | `cni-config` | Mount volume name. |
| `spec.vpcCni.env[].valueFrom.fileKeyRef.path` | `settings.conf` | File path in volume. |
| `spec.vpcCni.env[].valueFrom.fileKeyRef.key` | `ENABLE_PREFIX_DELEGATION` | Key inside env file format. |

**Useful for us:** Advanced VPC CNI tuning without huge inline env strings.

#### Status (controller-managed)

| Field | Example | Comment |
|-------|---------|---------|
| `status.observedGeneration` | `6` | Written by v2.12 controller; detects coalesced spec updates. **Requires updated CRD.** |
| `status.networkStatus.*.loadBalancerIPAddressType` | `dualstack` | Reports ELB IP mode (`ipv4`, `dualstack`, …). |
| `status.bastion.ipv6Address` | `2600:1f18:…` | Bastion IPv6 when enabled. |

---

### `AWSCluster` (+31 fields)

Used for **self-managed (EC2/kubeadm) clusters** and shared network spec patterns.

#### Load balancer / IPv6

| Field | Example | Comment |
|-------|---------|---------|
| `spec.controlPlaneLoadBalancer.targetGroupIPType` | `ipv6` | Target group addresses type for API server LB. |
| `spec.controlPlaneLoadBalancer.dnsResolutionCheck` | `Enabled` | Wait for LB DNS before proceeding (reduces kubeadm race). Default behavior documented in CAPA book. |
| `spec.secondaryControlPlaneLoadBalancer.*` | (same fields) | Secondary API server LB for HA / split scenarios. |

```yaml
spec:
  controlPlaneLoadBalancer:
    targetGroupIPType: ipv4
    dnsResolutionCheck: Enabled
  network:
    additionalNodeIngressRules:
      - protocol: tcp
        fromPort: 10250
        toPort: 10250
        cidrBlocks:
          - 10.0.0.0/16
```

**Useful for us:** Mainly if we run non-EKS CAPA clusters or share `AWSCluster` network templates. EKS teams mostly use `AWSManagedControlPlane` for network.

#### Status

Same bastion / `networkStatus` IPv6 fields as MCP (read-only, populated by controller).

---

### `AWSManagedMachinePool` (+16 fields)

EKS **managed node groups** (including MachinePool-based MNG).

| Field | Example | Comment |
|-------|---------|---------|
| `spec.nodeRepairConfig.enabled` | `true` | EKS node auto repair (replace unhealthy nodes). Default `false`. |
| `spec.lifecycleHooks[].name` | `LaunchWaitForTags` | ASG lifecycle hook name. |
| `spec.lifecycleHooks[].lifecycleTransition` | `autoscaling:EC2_INSTANCE_LAUNCHING` | `…LAUNCHING` or `…TERMINATING`. |
| `spec.lifecycleHooks[].defaultResult` | `CONTINUE` | `CONTINUE` or `ABANDON`. |
| `spec.lifecycleHooks[].heartbeatTimeout` | `300` | Seconds in wait state. |
| `spec.lifecycleHooks[].notificationTargetARN` | `arn:aws:sns:eu-west-1:123456789012:asg-hooks` | SNS/Lambda/SQS for hook events. |
| `spec.awsLaunchTemplate.enclaveOptions.enabled` | `true` | AWS Nitro Enclaves on MNG instances. |
| `spec.awsLaunchTemplate.instanceMetadataOptions.httpProtocolIpv6` | `enabled` | IMDS IPv6 endpoint. |
| `spec.rolePath` / `spec.rolePermissionsBoundary` | (see MCP) | IAM path / boundary for node role. |

```yaml
spec:
  nodeRepairConfig:
    enabled: true
  lifecycleHooks:
    - name: WaitForExternalConfig
      lifecycleTransition: autoscaling:EC2_INSTANCE_LAUNCHING
      defaultResult: CONTINUE
      heartbeatTimeout: "600"
      notificationTargetARN: arn:aws:sns:eu-west-1:123456789012:node-launch
  awsLaunchTemplate:
    instanceType: m6i.large
    enclaveOptions:
      enabled: false
```

**Useful for us:** `nodeRepairConfig` for hands-off node replacement; lifecycle hooks for custom launch gates. **Note:** our fork also fixes EKS MNG ASG tag propagation at create time (controller behavior, not a CRD field — see Appendix).

---

### `AWSMachinePool` (+21 fields)

Self-managed **MachinePool** (ASG-based workers, not EKS MNG).

| Field | Example | Comment |
|-------|---------|---------|
| `spec.lifecycleHooks[]` | (same as MMP) | Hooks on the MachinePool ASG. |
| `spec.ignition.version` | `3.4` | Ignition spec version for FCOS/RHCOS-style bootstrap. |
| `spec.ignition.storageType` | `ClusterObjectStore` | Where bootstrap userdata is stored. |
| `spec.ignition.proxy.httpProxy` | `http://proxy.corp:8080` | Proxy for Ignition fetch. |
| `spec.awsLaunchTemplate.enclaveOptions.enabled` | `true` | Nitro Enclaves. |

**Useful for us:** Only if we use CAPA MachinePools outside EKS (uncommon in EKS-only setups).

---

### `AWSMachine` (+12 fields)

Single **EC2 worker / control-plane machine**.

| Field | Example | Comment |
|-------|---------|---------|
| `spec.assignPrimaryIPv6` | `enabled` | Primary IPv6 on primary ENI. |
| `spec.cpuOptions.nestedVirtualization` | `enabled` | Nested virtualization on instance. |
| `spec.cpuOptions.confidentialCompute` | `Disabled` | Confidential computing mode. |
| `spec.hostID` | `h-0123456789abcdef0` | Pin instance to dedicated host. |
| `spec.dynamicHostAllocation.tags` | `{"project": "prod"}` | Auto-allocate dedicated host with tags. |
| `status.dedicatedHost.id` | `h-0abc…` | Populated when dynamic host allocation used. |

```yaml
spec:
  instanceType: m6i.xlarge
  assignPrimaryIPv6: enabled
  instanceMetadataOptions:
    httpProtocolIpv6: enabled
```

**Useful for us:** IPv6-only or dual-stack node networking; niche compliance (dedicated hosts, enclaves).

---

### `AWSMachineTemplate` (+20 fields)

Wraps `AWSMachine` spec in templates / ClusterClass. New fields mirror `AWSMachine` plus:

| Field | Example | Comment |
|-------|---------|---------|
| `status.conditions[]` | `type: Ready` | Template readiness conditions (CAPI contract). |
| `status.nodeInfo.operatingSystem` | `linux` | Reported OS from referenced machines. |

---

### `AWSClusterTemplate` (+16 fields)

Template mirror of new `AWSCluster` LB and `additionalNodeIngressRules` fields under `spec.template.spec.*`.

---

### `AWSFargateProfile` (+2 fields)

| Field | Example | Comment |
|-------|---------|---------|
| `spec.rolePath` | `/fargate/` | IAM role path for Fargate pod execution role. |
| `spec.rolePermissionsBoundary` | `arn:aws:iam::…:policy/Boundary` | Permissions boundary. |

---

### `ROSAControlPlane` (+22 fields)

Only relevant for **Red Hat OpenShift on AWS (ROSA)** via CAPA experimental controllers.

| Field | Example | Comment |
|-------|---------|---------|
| `spec.fips` | `true` | FIPS-compliant OpenShift. |
| `spec.channel` | `stable-4.16` | OpenShift upgrade channel (Y-stream support). |
| `spec.rosaNetworkRef.name` | `prod-network` | Link to `ROSANetwork` CR. |
| `spec.rosaRoleConfigRef.name` | `prod-roles` | Link to `ROSARoleConfig` CR. |
| `spec.trustPolicyExternalID` | `unique-external-id` | STS `ExternalId` for cross-account roles. |
| `spec.cloudWatchlogForwarder.*` | (app list, log group) | Forward ROSA logs to CloudWatch. |
| `spec.s3LogForwarder.*` | (bucket, prefix) | Forward ROSA logs to S3. |
| `spec.autoNode.mode` | `auto` | ROSA auto-scaling node mode. |
| `status.availableChannels` | `["stable-4.16", …]` | Discovered upgrade channels. |

---

### `NodeadmConfig` (+71 fields, new kind)

Bootstrap provider for **self-managed** Kubernetes nodes using nodeadm (alternative to kubeadm bootstrap templates).

Representative fields:

| Field | Example | Comment |
|-------|---------|---------|
| `spec.files[].path` | `/etc/kubernetes/pki/ca.crt` | Files to write on node. |
| `spec.files[].content` | `LS0tLS1CRUdJTi…` | Base64 or inline content. |
| `spec.diskSetup.partitions[].device` | `/dev/nvme1n1` | Disk layout for Ignition-style setup. |
| `spec.featureGates` | `{"KubeletInUserNamespace": true}` | K8s feature gates on node. |
| `spec.containerd.config` | (TOML string) | containerd config fragment. |

**Useful for us:** Only if adopting CAPA for kubeadm/self-managed clusters with modern nodeadm bootstrap.

---

### `ROSANetwork`, `ROSARoleConfig`, `ROSAOCMRoleConfig` (new kinds)

Support objects for ROSA multi-account / network / IAM automation. Typical pattern:

```yaml
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: ROSANetwork
metadata:
  name: prod-network
spec:
  # VPC / subnet / machine CIDR definitions for ROSA
---
apiVersion: infrastructure.cluster.x-k8s.io/v1beta2
kind: ROSARoleConfig
metadata:
  name: prod-roles
spec:
  # Account roles, installer / support / worker role ARNs or creation params
```

Skip unless ROSA on CAPA is on the roadmap.

---

### `AWSManagedControlPlaneTemplate` / `AWSManagedClusterTemplate` (new kinds)

ClusterClass-compatible templates. Example skeleton:

```yaml
apiVersion: controlplane.cluster.x-k8s.io/v1beta2
kind: AWSManagedControlPlaneTemplate
metadata:
  name: eks-standard
spec:
  template:
    spec:
      region: eu-west-1
      version: "1.31"
      accessConfig:
        authenticationMode: api_and_config_map
      # … defaults for all clusters using this class
```

**Useful for us:** Standardize EKS MCP defaults across tenants if using ClusterClass.

---

## Thematic grouping (what might matter most)

### High priority for EKS production

| Feature | Resource | Why |
|---------|----------|-----|
| EKS Access API | `AWSManagedControlPlane` | Future-proof auth; reduce `aws-auth` drift |
| `status.observedGeneration` | `AWSManagedControlPlane` | Correct reconciliation after upgrade |
| `upgradePolicy` | `AWSManagedControlPlane` | Cost control vs extended support |
| `nodeRepairConfig` | `AWSManagedMachinePool` | Less manual node replacement |
| `preserveOnDelete` on addons | `AWSManagedControlPlane` | Safer addon lifecycle |
| `rolePermissionsBoundary` | MCP, MMP, Fargate | Enterprise IAM compliance |

### Medium priority

| Feature | Resource | Why |
|---------|----------|-----|
| `additionalNodeIngressRules` | MCP / AWSCluster | SG rules as code |
| `dnsResolutionCheck` | AWSCluster LB | Stability for self-managed CP |
| IPv6 / dual-stack LB fields | AWSCluster, MCP status | Dual-stack roadmap |
| `lifecycleHooks` | MMP / MachinePool | Custom launch/terminate automation |

### Low priority (unless specific need)

| Feature | Resource | Why |
|---------|----------|-----|
| Nitro Enclaves | MMP, MachinePool, AWSMachine | Confidential computing |
| Dedicated hosts | AWSMachine | License / compliance pinning |
| Ignition bootstrap | MachinePool | Non-EKS FCOS |
| ROSA * | ROSA* CRDs | Not EKS |
| Nodeadm * | NodeadmConfig | Not EKS MNG |

---

## Appendix A — Fork additions (v2.12.2+, not in upstream v2.12.1)

This repository’s **release/v2.12.2** branch adds the following on top of v2.12.1:

| Item | Location | Example |
|------|----------|---------|
| `singleNatGateway` | `spec.network.vpc` on `AWSCluster` / `AWSManagedControlPlane` | `singleNatGateway: true` — one NAT for all private subnets (cost saving; not AZ-HA) |
| EKS MNG ASG tag fix | Controller (`nodegroup.go`) | Creates MNG with `DesiredSize`/`MinSize` 0 until tags propagate — **behavior**, not a CRD field |
| Release workflows / Goreleaser | `.github/workflows`, `.goreleaser.yaml` | Image publish automation |

```yaml
spec:
  network:
    vpc:
      cidrBlock: 10.0.0.0/16
      # Default (omit/false): one NAT per AZ (upstream).
      # true: single shared NAT across AZs.
      singleNatGateway: true
```

When comparing **v2.8.2 → v2.12.1**, treat `singleNatGateway` as **fork-only** unless you deploy this fork’s image and CRDs.

---

## Appendix B — Full field addition counts

| Kind | +fields | −fields |
|------|---------|---------|
| AWSManagedControlPlane | 48 | 0 |
| AWSCluster | 31 | 0 |
| AWSMachinePool | 21 | 0 |
| AWSMachineTemplate | 20 | 0 |
| AWSManagedMachinePool | 16 | 0 |
| AWSClusterTemplate | 16 | 0 |
| AWSMachine | 12 | 0 |
| AWSManagedClusterTemplate | 9 | 0 |
| ROSAControlPlane | 22 | 0 |
| ROSAMachinePool | 2 | 0 |
| AWSFargateProfile | 2 | 0 |
| NodeadmConfig | 71 (new) | 0 |
| NodeadmConfigTemplate | 58 (new) | 0 |
| AWSManagedControlPlaneTemplate | 187 (new) | 0 |
| ROSANetwork | 31 (new) | 0 |
| ROSAOCMRoleConfig | 25 (new) | 0 |
| ROSARoleConfig | 49 (new) | 0 |
| *Identity / EKSConfig / AWSManagedCluster / ROSACluster* | 0 | 0 |

---

## Appendix C — Suggested review checklist for expert session

1. **Auth:** Stay on `aws-auth` vs migrate to `accessEntries` — timeline and tooling impact?
2. **Upgrade policy:** `standard` vs `extended` for our EKS fleet — cost model?
3. **CRD rollout:** Can management clusters apply all v2.12 CRDs in one maintenance window?
4. **Node repair:** Enable `nodeRepairConfig` on production MNGs?
5. **Network:** Need `additionalNodeIngressRules` or `singleNatGateway` (fork) for cost / access?
6. **Addons:** Use `preserveOnDelete` for vpc-cni / ebs-csi during upgrades?
7. **Scope:** Any self-managed CAPA clusters needing AWSCluster / Nodeadm / Ignition fields?
8. **ROSA:** Ignore new ROSA CRDs or evaluate separately?

---

## References

- Tags compared: `v2.8.2` … `v2.12.1` in [kubernetes-sigs/cluster-api-provider-aws](https://github.com/kubernetes-sigs/cluster-api-provider-aws)
- [CAPA book — EKS](https://cluster-api-aws.sigs.k8s.io/topics/eks/)
- [EKS access entries](https://docs.aws.amazon.com/eks/latest/userguide/access-entries.html)
- [EKS upgrade policies](https://docs.aws.amazon.com/eks/latest/userguide/view-upgrade-policy.html)

*Generated from CRD OpenAPI diff in this repository. Re-run diff after cherry-picks or fork merges.*
