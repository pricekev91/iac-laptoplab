# Architecture

## 1. Project Vision

### 1.1 Purpose

Build a self-hosted, vendor-agnostic AI appliance that provides local LLM inference, UI access, agentic access, future orchestration, and supporting tooling across multiple machines using reproducible Infrastructure-as-Code.

### 1.2 Requirements

The system must:

- Operate fully offline during real-world use after an online build, update, and preload phase
- Avoid paid AI services
- Be hardware-agnostic across supported CPU and GPU combinations
- Be reproducible, auditable, and long-lived
- Support snapshots and rollback as first-class lifecycle operations
- Require idempotent bootstrap and apply workflows, or explicit prerequisite failures when idempotency cannot be achieved automatically

### 1.3 Long-Term Objective

A portable, deterministic AI platform that can:

- Bootstrap on any compatible host
- Migrate across hardware generations
- Extend with new models, UIs, and tooling
- Maintain stability with minimal drift

## 2. High-Level Architecture

### 2.1 Logical Layers

- Host Layer: Minimal OS plus LXD substrate
- Platform Layer: LXD projects `ai-infra` and `ai-dev`
- Service Layer: Containers providing inference, UI, agentic services, and future orchestration
- Client Layer: Editors, browsers, and CLI tools consuming API and UI endpoints

### 2.2 Physical Layout

Initial host:

- Alienware M17 R2 running CachyOS or another Arch-family distribution

Future hosts:

- MINISFORUM N5 Pro running Proxmox or Debian-family Linux
- Additional compatible hosts

Each host runs:

- Arch-family Linux or Debian/Proxmox
- LXD daemon
- IaC-driven configuration

### 2.3 Component Relationships

- Host OS -> LXD
- LXD -> Projects
- Projects -> Containers
- Containers -> Shared model storage
- Clients -> API and UI endpoints

### 2.4 Data Flow

1. Client sends prompt.
2. API container loads the configured model.
3. GPU or CPU performs inference.
4. Response is returned to the client.

## 3. Technology Stack

### 3.1 Host OS

- Arch Linux or CachyOS
- Debian or Proxmox 9.x

### 3.2 Virtualization

- LXD system containers
- LXD projects for isolation

### 3.3 AI Stack

- `llama.cpp` now
- Additional VLM or multimodal runtimes later after architecture review
- GGUF model format today
- Shared host model directory mounted read-only into both production and development containers

### 3.4 UI Stack

- Web-based UI such as Open WebUI
- Editor integrations via HTTP API

### 3.5 IaC Stack

- Git-tracked Infrastructure-as-Code
- Bash scripts
- YAML inventory and platform definitions
- Deterministic apply runner
- Modular bootstrap scripts behind a single top-level operator workflow

### 3.6 Networking

- LXD bridge networking
- Local-only by default
- Explicit opt-in for LAN exposure

## 4. IaC Structure and Contracts

### 4.1 Repository Layout

```text
iac-laptoplab/
├── bootstrap/          # Host bootstrap scripts
├── inventory/          # Host-specific YAML configs
├── platforms/          # Declarative container definitions
├── profiles/           # LXD profile definitions
├── docs/
│   └── architecture.md
├── apply.bash          # Inventory-driven apply runner
└── README.md
```

### 4.2 Inventory Schema

Example: `inventory/alienware-m17r2.yaml`

```yaml
host:
  id: alienware-m17r2
  os: arch
  gpu: nvidia
  cpu: intel
  ram_gb: 32
  storage_root: /srv
  model_dir: /srv/models

projects:
  - ai-infra
  - ai-dev

platforms:
  - llama
  - openwebui

network:
  expose_ui: false
```

Contract:

- `host.*` drives bootstrap selection, package logic, and GPU profile mapping
- `host.model_dir` is the canonical shared GGUF storage root for both `ai-infra` and `ai-dev`
- `projects` defines required LXD projects
- `platforms` defines which platform YAMLs to apply
- `network.expose_ui` controls localhost-only versus LAN binding policy

### 4.3 Platform Definition Schema

Example: `platforms/llama.yaml`

```yaml
name: llama
project: ai-infra
variant:
  default: cpu
  supported:
    - cpu
    - nvidia
    - amd
  select_from: host.gpu

container:
  name: llama
  image: images:ubuntu/24.04
  profiles:
    - default
    - gpu
  mounts:
    - host: "{{ host.model_dir }}"
      container: /models
      readonly: true
  env:
    LLAMA_MODEL: /models/default.gguf
  command: >
    /usr/local/bin/llama-server --model $LLAMA_MODEL --host 0.0.0.0 --port 8080

ports:
  - host: 8080
    container: 8080
    bind_local_only: true
```

Example: `platforms/openwebui.yaml`

```yaml
name: openwebui
project: ai-dev
variant:
  default: cpu
  supported:
    - cpu
    - nvidia
    - amd
  select_from: host.gpu

container:
  name: openwebui
  image: images:ubuntu/24.04
  profiles:
    - default
  mounts:
    - host: "{{ host.model_dir }}"
      container: /models
      readonly: true
  env:
    BACKEND_URL: http://llama.ai-infra:8080
  command: >
    /usr/local/bin/openwebui --host 0.0.0.0 --port 3000

ports:
  - host: 3000
    container: 3000
    bind_local_only: true
```

### 4.4 LXD Profiles

Profiles live under `profiles/`:

- `gpu-nvidia.yaml`
- `gpu-amd.yaml`
- `gpu-intel.yaml`

Contract:

- Inventory selects the effective GPU profile
- Containers requiring GPU include the generic `gpu` role, which the apply runner resolves to the concrete vendor profile
- Variant selection remains in the platform definition, while GPU passthrough remains in the resolved LXD profile layer

### 4.5 Apply Runner Contract

`apply.bash` performs deterministic, idempotent provisioning.

End-state workflow:

1. A fresh compatible host runs the OS-specific bootstrap path to install and initialize LXD.
2. `apply.bash` validates that host prerequisites are present and may dispatch the OS-specific bootstrap path when they are absent or unready.
3. `apply.bash` reconciles LXD projects, profiles, containers, storage mounts, environment, and service exposure.

Operator experience target:

- One command from the operator point of view
- Multiple focused scripts under the hood for bootstrap, validation, and reconciliation
- Safe reruns after the first successful bootstrap
- Explicit idempotency guarantees for both bootstrap and apply stages

Execution flow:

1. Load inventory.
2. Ensure LXD is installed and initialized.
3. Create LXD projects.
4. Apply LXD profiles.
5. For each platform:
6. Create or update container.
7. Apply profiles, mounts, environment, and command.
8. Configure port bindings.
9. Replace containers when platform changes require a clean rollout, then start the replacement deterministically.
10. Create LXD snapshots before destructive mutation.

Properties:

- Idempotent
- Deterministic
- Inventory-driven
- Auditable through file-defined desired state

## 5. Bootstrap and Lifecycle

### 5.1 Provisioning Flow

1. Fresh OS install.
2. Clone repo.
3. Run host bootstrap script.
4. Log out and back in if required by group or driver changes.
5. Run `./apply.bash inventory/<host>.yaml`.

### 5.2 Build Flow

- Containers are created from declarative YAML definitions
- Models are mounted, not baked into images
- GPU access is passed through via profiles
- Build and update operations are allowed to use the network; field operation is expected to be offline

### 5.3 Deployment Flow

- Inventory selects host profile
- Apply runner provisions projects, containers, mounts, and runtime settings
- Production containers are replaced rather than mutated in place when significant platform changes are applied
- Services start deterministically

### 5.4 Snapshot and Rollback Flow

- LXD snapshots are the primary rollback mechanism before mutation
- Model storage remains external to containers where possible
- Rollback procedures must restore both container state and matching configuration revision
- Host filesystem snapshots such as ZFS or Btrfs remain optional enhancements, not the primary contract

## 6. Current State vs Target State

### 6.1 Implemented

- First Arch/CachyOS bootstrap script
- LXD substrate selected
- Local GGUF models plus working `llama.cpp` validated manually

### 6.2 Partially Implemented

- Inventory directory
- Platform directory
- Architecture baseline
- First apply runner slice

### 6.3 Not Implemented Yet

- Debian/Proxmox bootstrap
- Full apply runner with replacement rollout and snapshot orchestration
- Multi-host orchestration
- Snapshot and rollback automation

## 7. Environment Assumptions

- x86-64 hardware
- NVIDIA RTX 2060 Mobile GPU today
- AMD 890M expected later
- Intel GPU support is possible but lower priority
- Local SSD storage
- Shared model directory defined by inventory
- LAN-first environment with local-only defaults

## 8. Security Model

- LXD container isolation
- Project-level separation between `ai-infra` and `ai-dev`
- Minimal host privileges
- GPU access only where required
- Local-only network exposure by default
- `ai-dev` must not communicate directly with `ai-infra`
- LAN exposure for production services is allowed when explicitly enabled and managed on the host

## 9. Automation Goals

Fully automated:

- Host bootstrap
- LXD project creation
- Container provisioning
- Model mounting
- Service startup

Manual:

- Base OS installation
- Initial bootstrap invocation
- Model downloads unless mirrored or preseeded internally
- Promotion judgment for production changes

## 10. Roadmap

### 10.1 Immediate

- Expand `apply.bash` with replacement rollout logic
- Add LXD snapshot orchestration before destructive mutation
- Add host-specific inventory files beyond `alienware-m17r2`

### 10.2 Short-Term

- Harden inference and UI containers
- Add basic monitoring

### 10.3 Long-Term

- Multi-host orchestration
- Snapshot and rollback strategy
- Hardware migration support
- Runtime abstraction for future support of LXD, Incus, or Podman-backed workflows

## 11. Risks

- GPU driver variability
- LXD passthrough edge cases
- VRAM limits
- Disk I/O contention
- Tooling churn
- Over-customization

## 12. Design Principles

- Reproducibility over speed
- Explicitness over convenience
- Long-term maintainability over short-term shortcuts
- YAML, Bash, and Git as the primary IaC control surface
- Layered, hardware-agnostic design

## 13. Architectural Notes

The architecture is sound, but these constraints should remain explicit as implementation starts:

- Fully offline operation applies to field use, not initial build; online build and preload are part of the intended lifecycle.
- `apply.bash` should remain the single canonical runner name; avoid alternating between `apply.sh` and `apply.bash`.
- GPU profile selection should resolve from inventory into concrete vendor profiles rather than requiring platform YAML to know hardware specifics.
- Snapshot and rollback need to be treated as part of normal lifecycle management, not a later add-on.
- A shared host model store under `/srv/models` is the canonical model source for both production and development environments.
- Development and production remain isolated; validated changes are promoted by replacement and rollback, not by direct cross-project coupling.