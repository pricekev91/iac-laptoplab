# iac-laptoplab

Infrastructure-as-Code repository for a self-hosted, vendor-agnostic AI appliance built on Linux hosts, LXD system containers, and local model serving.

The previous Windows 11 and WSL-focused implementation has been archived in git and is intentionally not carried forward on `main`.

## Goal

Build toward an LXD-based deployment model where the AI stack is split into separate containers by responsibility:

- LLM engine container for inference runtime and model serving
- Web inference container for browser-based interaction
- Agent container for editor and automation-facing workflows

The intended direction is to keep these services loosely coupled, inventory-driven, and replaceable independently during rollout.

Operationally, the end-state should feel like one command from a fresh host, while still being implemented as modular scripts underneath:

- `bootstrap/<os>.bash` prepares a clean host, installs and initializes LXD, and establishes the host prerequisites
- `apply.bash` validates the host state, invokes the OS bootstrap path when first-run LXD prerequisites are missing, and then reconciles the LXD projects, profiles, containers, mounts, and service wiring
- the top-level workflow should be safe to rerun, with bootstrap handling first-time host preparation and apply handling ongoing reconciliation

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

`apply.bash` is the main operator entrypoint. In apply mode it can bootstrap an Arch/CachyOS host into a usable LXD baseline before reconciling the declared container state.

## Archived Legacy State

The previous repo state was preserved locally as:

- branch: `archive/windows-wsl-legacy`
- tag: `archive-windows-wsl-2026-04-22`

## Next Build Targets

1. Expand `apply.bash` with replacement rollout and LXD snapshot orchestration.
2. Make first-run host bootstrap and LXD initialization part of the end-to-end workflow from a clean machine.
3. Break the stack into distinct LXD service containers for LLM engine, web inference, and agent workloads.
4. Add production and dev service hardening.
5. Add monitoring and promotion workflows.
6. Refine Intel GPU profile once Intel hardware is available.
