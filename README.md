# iac-laptoplab

Infrastructure-as-Code repository for a self-hosted, vendor-agnostic AI appliance built on Linux hosts, LXD system containers, and local model serving.

The previous Windows 11 and WSL-focused implementation has been archived in git and is intentionally not carried forward on `main`.

## Goal

Build toward an LXD-based deployment model where the AI stack is split into separate containers by responsibility:

- LLM engine container for inference runtime and model serving
- Web inference container for browser-based interaction
- Agent container for editor and automation-facing workflows

The intended direction is to keep these services loosely coupled, inventory-driven, and replaceable independently during rollout.

## Current Scope

- Linux host bootstrap for Arch-family and Debian-family systems
- LXD projects for infrastructure and development isolation
- Declarative platform definitions for separate LLM, web, and agent services
- Inventory-driven provisioning with deterministic, auditable state
- Offline-first operation, with explicit handling for mirrored artifacts and model storage

## Repository Layout

```text
iac-laptoplab/
├── bootstrap/
├── docs/
│   └── architecture.md
├── inventory/
├── platforms/
├── profiles/
├── apply.bash
└── README.md
```

## Starting Point

The architectural baseline lives in `docs/architecture.md`.

Seed files included now:

- `bootstrap/arch-cachyos.bash`
- `inventory/alienware-m17r2.yaml`
- `platforms/llama.yaml`
- `platforms/openwebui.yaml`
- `profiles/gpu-nvidia.yaml`
- `profiles/gpu-amd.yaml`
- `profiles/gpu-intel.yaml`
- `apply.bash`

`apply.bash` is currently a deterministic scaffold and validation entrypoint, not a full provisioner yet.

## Archived Legacy State

The previous repo state was preserved locally as:

- branch: `archive/windows-wsl-legacy`
- tag: `archive-windows-wsl-2026-04-22`

## Next Build Targets

1. Expand `apply.bash` with replacement rollout and LXD snapshot orchestration.
2. Break the stack into distinct LXD service containers for LLM engine, web inference, and agent workloads.
3. Add production and dev service hardening.
4. Add monitoring and promotion workflows.
5. Refine Intel GPU profile once Intel hardware is available.
