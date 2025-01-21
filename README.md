# cluster-deps.bootstrap.infra

[![Release](https://img.shields.io/github/v/release/edenlabllc/cluster-deps.bootstrap.infra.svg?style=for-the-badge)](https://github.com/edenlabllc/cluster-deps.bootstrap.infra/releases/latest)
[![Software License](https://img.shields.io/github/license/edenlabllc/cluster-deps.bootstrap.infra.svg?style=for-the-badge)](LICENSE)
[![Powered By: Edenlab](https://img.shields.io/badge/powered%20by-edenlab-8A2BE2.svg?style=for-the-badge)](https://edenlab.io)

## Description

This repository provides a general set of [Cluster API](https://cluster-api.sigs.k8s.io) and system components
required for provisioning of Kubernetes clusters for different providers.
It is inherited by other tenant repositories.
Mainly, it is designed to be managed by administrators, DevOps engineers, SREs.

## Getting Started

To get started with cluster-deps.bootstrap.infra, ensure you have all the necessary tools and dependencies installed. 
Detailed information about requirements and installation instructions can be found in the [Requirements](#requirements) section.

### Requirements

- Git
- Note: K3D v5.x.x requires at least Docker v20.10.5 (runc >= v1.0.0-rc93) to work properly
- [RMK CLI](https://edenlabllc.github.io/rmk/latest)

### GitLab flow strategy

This repository uses the Environment branches with GitLab flow approach,
where each stable or ephemeral branches is a separate environment with its own Kubernetes cluster.

Release schema:
```text
develop ------> staging ------> production
   \            /     \           /
  release/vN.N.N-rc  release/vN.N.N
```

### Generating project structure

> Note: The generated project structure using the RMK tools is mandatory and is required for the interaction of the RMK with the code base. 
> All generated files have example content and can be supplemented according to project requirements.

This example shows how the following options are configured and interact with each other:

- etc/deps/\<environment>/secrets/.spec.yaml.gotmpl
- etc/deps/\<environment>/values/*.yaml.gotmpl
- etc/deps/\<environment>/globals.yaml.gotmpl
- etc/deps/\<environment>/releases.yaml
- .gitignore
- helmfile.yaml.gotmpl
- project.yaml


#### Available scopes of variables

- **deps**

### Basic RMK commands for project management

#### Project generate

```shell
rmk project generate \
    --environment=develop.root-domain=localhost \
    --owners=user \
    --scopes=deps
```

#### Initialization configuration

```shell
rmk config init
```

#### Create CAPI cluster

```shell
rmk cluster capi create
```

#### Release sync

```shell
rmk release sync
```

> Note: A complete list of RMK commands and capabilities can be found at the [link](https://edenlabllc.github.io/rmk/latest)
