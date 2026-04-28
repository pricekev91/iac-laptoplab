# iac-laptoplab

Infrastructure-as-Code repository for a self-hosted, vendor-agnostic AI appliance built on Linux hosts, LXD system containers, and local model serving.

The previous Windows 11 and WSL-focused implementation has been archived in git and is intentionally not carried forward on `main`.

## Goal

Build toward an LXD-based deployment model where the AI stack is split into separate containers by responsibility:

- LLM engine container for inference runtime and model serving
- Web inference container for browser-based interaction
- Agent container for editor and automation-facing workflows

The intended direction is to keep these services loosely coupled, inventory-driven, and replaceable independently during rollout.

Current naming contract:

- projects represent environments; today the inventory targets only `prod`
- platform and container names represent service roles: `engine`, `presentation`, `orchestrator`, `agents`

Operationally, the end-state should feel like one command from a fresh host, while still being implemented as modular scripts underneath:

- `bootstrap/<os>.bash` prepares a clean host, installs and initializes LXD, and establishes the host prerequisites
- `apply.bash` validates the host state, invokes the OS bootstrap path when first-run LXD prerequisites are missing, and then reconciles the LXD projects, profiles, containers, mounts, and service wiring
- the top-level workflow should be safe to rerun, with bootstrap handling first-time host preparation and apply handling ongoing reconciliation

Idempotency is a design requirement for both layers:

- bootstrap must be safe to rerun on a partially prepared host and either converge cleanly or fail with an explicit prerequisite error
- apply must be safe to rerun against an already bootstrapped host and converge the declared LXD state without hidden one-time assumptions
- runtime provisioning inside containers must reuse installed packages, source trees, and built artifacts whenever the declared inputs have not changed

## Current Scope

- Linux host bootstrap for Arch-family and Debian-family systems
- LXD projects with a single active `prod` environment and optional future expansion
- Declarative platform definitions for engine, presentation, orchestrator, and agent services
- Inventory-driven provisioning with deterministic, auditable state
- Idempotent bootstrap and apply behavior as a first-class requirement
- Offline-first operation, with explicit handling for mirrored artifacts and model storage

## Rerun Contract

Normal reruns should be fast and boring:

- unchanged projects, profiles, devices, environment, and proxy bindings are left in place
- unchanged containers are not replaced
- unchanged runtime installers are not supposed to redownload packages or source archives
- unchanged services are not supposed to be rebuilt or restarted just because `apply.bash` ran again

Network-heavy work is expected only when one of these inputs changes:

- the platform definition changes in a way that alters desired container state
- the runtime install script changes
- the runtime service is missing, failed, or otherwise unhealthy and must be repaired
- the target container has never completed its first successful provisioning run

## Repository Layout

```text
iac-laptoplab/
├── bootstrap/
├── docs/
│   └── architecture.md
├── inventory/
├── platforms/
├── profiles/
├── scripts/
├── apply.bash
└── README.md
```

## Starting Point

The architectural baseline lives in `docs/architecture.md`.

The current prod endpoint inventory, including canonical host URLs and observed live container addresses, lives in `docs/architecture.md#44-current-prod-endpoint-inventory`.

Current local service URLs:

- Open WebUI: `http://127.0.0.1:3000`
- n8n: `http://127.0.0.1:5678`
- AI Engine: `http://127.0.0.1:8080`
- Agents: `http://127.0.0.1:7788`

Known-good validation snapshot as of 2026-04-28:

- `presentation` verified working through Open WebUI on `http://127.0.0.1:3000`
- `orchestrator` verified working through n8n on `http://127.0.0.1:5678`
- `engine` verified working through the AI Engine endpoint on `http://127.0.0.1:8080`
- `agents` remains part of the declared architecture, but is not part of the current three-component known-good baseline

The `orchestrator` runtime now installs `@bpmsoftwaresolutions/ai-engine-client` so n8n code nodes can call the deployed AI Engine directly. Keep the base URL in inventory and pass the API key at apply time, for example `AI_ENGINE_CLIENT_API_KEY=... ./apply.bash inventory/alienware-m17r2.yaml`.

Seed files included now:

- `bootstrap/arch-cachyos.bash`
- `inventory/alienware-m17r2.yaml`
- `platforms/engine.yaml`
- `platforms/presentation.yaml`
- `platforms/orchestrator.yaml`
- `platforms/agents.yaml`
- `scripts/provision-ai-engine.bash`
- `scripts/provision-openwebui.bash`
- `scripts/provision-n8n.bash`
- `scripts/provision-crewai.bash`
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

1. Harden the new `orchestrator` and `agents` services beyond baseline package install and startup.
2. Add monitoring and promotion workflows.
3. Add mirrored artifact and package cache support for stricter offline rebuild behavior.
4. Reintroduce a separate `dev` environment only when there is a concrete need for it.
5. Refine Intel GPU profile once Intel hardware is available.
