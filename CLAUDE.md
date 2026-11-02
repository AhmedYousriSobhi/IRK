# AI Assistant Instructions for IRK (Infrastructure Run Kit)

## Project Context
You are assisting with **IRK**, a collective repository containing daily operational support scripts, telemetry tools, and experimental lab setups for High-Performance Computing (HPC) and AI Infrastructure engineering.

## Domain Knowledge
- **Primary OS environment:** Linux (Rocky/Alma Linux 9, Ubuntu).
- **Core Technologies:** Slurm, CUDA, NVIDIA DCGM, MPI, Vagrant, Ansible, Docker/Singularity.
- **Hardware Context:** GPU clusters, Multi-node distributed setups, login/compute node topologies.

## Coding Standards & Guidelines

### 1. Scripting (`bin/` and `support/`)
- Prefer pure Bash (`#!/usr/bin/env bash`) or standard Python 3 for portability.
- **Zero-dependency efficiency:** Avoid introducing heavy third-party libraries unless absolutely necessary.
- **Safety first:** Bash scripts must use `set -euo pipefail`.
- **Idempotency:** Operational scripts should be safe to run multiple times without causing duplicate configurations or destructive overwrites.
- Include a `--help` or `-h` flag for executable scripts in `bin/` explaining usage and required flags.

### 2. Lab Environments (`labs/`)
- Labs must be entirely reproducible and contained within their own directories.
- Default to lightweight constraints unless specified (e.g., 1GB RAM per VM for local multi-node tests).
- Configuration as Code: Prefer declarative setups (Vagrantfiles, Ansible playbooks) over manual shell provisioning steps where possible.

### 3. Documentation
- Write documentation in clean, standard Markdown.
- Keep explanations empirical and structural.
- When generating architecture diagrams or trees, use standard markdown code blocks (`text` or `mermaid`).

## Interaction Protocol
- When asked to create a new lab, always include a local `README.md` for that specific lab.
- Do not modify `SPEC.md` unless explicitly instructed to update the architectural design.
- If a user requests a new operational script, check if it belongs in the global `bin/` (daily CLI use) or a specific `labs/` directory (environment-specific).