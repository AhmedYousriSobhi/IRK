# IRK (Infrastructure Run Kit) Specification

## 1. Vision & Purpose
**IRK** is a unified toolkit and sandbox environment for HPC and AI infrastructure engineers. It bridges daily operational support and experimental development.

It serves two functions:
1. **Support Tools:** a centralized set of scripts and utilities for cluster telemetry, node debugging, and daily operations, run directly on live clusters or local machines.
2. **Lab Environments:** isolated, reproducible environments (e.g., multi-node Vagrant setups) used to simulate, benchmark, and test infrastructure changes before deploying to bare metal.

**Target environment:** Linux (Rocky/Alma 9, Ubuntu); Slurm, CUDA, NVIDIA DCGM, MPI, Vagrant, Ansible, Docker/Singularity; GPU clusters with login/compute node topologies.

## 2. Directory Architecture

```text
irk/
├── bin/                 # Executable operational CLI tools (add to $PATH)
├── support/             # Domain-specific helpers, telemetry, diagnostics
│   ├── cluster/         # Slurm, node states, job orchestration
│   ├── gpu/             # DCGM, NVIDIA bindings, CUDA validations
│   └── storage/         # I/O benchmarking and filesystem checks
├── labs/                # Reproducible sandbox environments
│   └── template/        # Boilerplate for creating a new lab
├── docs/                # Local wiki; mirrored to the GitHub wiki
├── .github/             # PR template and repo automation
├── CLAUDE.md            # AI assistant rules
├── SPEC.md              # Project specification and architecture
└── README.md            # Entry point and quickstart
```

Directories are created when the first feature needs them.

## 3. Lab Specification

Every environment in `labs/` MUST be modular and understandable:

- **Self-contained:** a lab does not depend on files outside its own directory, except documented global `bin/` tools.
- **Reproducible:** declarative configuration (Vagrantfile, Ansible playbooks, docker-compose.yml, hosts.ini) is preferred over manual provisioning steps.
- **Lightweight by default:** e.g., 1 GB RAM per VM unless the lab states otherwise.
- **Required files:**
  - `README.md`: purpose, architecture (e.g., 1 login node + 2 compute nodes), and OS/RAM constraints.
  - A configuration file (`Vagrantfile`, `docker-compose.yml`, or `hosts.ini`).
- **Recommended:** `up.sh` / `down.sh` wrappers (e.g., around `vagrant up` / `vagrant destroy`).
- **Naming:** lowercase, hyphenated directory names (e.g., `hpc-pocket-cluster`).
- Start new labs by copying `labs/template/`.

## 4. Execution Model

- **`bin/` tooling** is executed directly on live clusters or local machines. Users add `irk/bin` to `$PATH`.
- **Naming:** script names are hyphenated, lowercase, and descriptive (e.g., `node-drain`, `gpu-health-check`).
- **Placement:** daily CLI tools go in `bin/`; environment-specific scripts go in the relevant `labs/<name>/`; reusable helpers go in `support/`.
- **Script standards** (`bin/`, `support/`):
  - Pure Bash (`#!/usr/bin/env bash`) or standard Python 3, with no third-party dependencies unless unavoidable.
  - Bash scripts use `set -euo pipefail`.
  - Operational scripts are idempotent.
  - Executables in `bin/` provide `--help` / `-h`.

## 5. Documentation & Workflow

### Documentation
- All project documentation lives in `docs/` as a **local wiki** and is mirrored to the **GitHub wiki**. `docs/` is the source of truth; flat file names (`Home.md`, `Development-Workflow.md`, ...) so they map 1:1 to wiki pages.
- Every feature, modification, or lab updates the relevant `docs/` page (and `README.md` when user-facing) in the same PR.
- Each lab additionally keeps its own `README.md`.

### Branching and change flow
- `main`: stable; receives merges from `dev` after several milestones.
- `dev`: integration branch; all work targets it.
- For every feature, modification, or fix:
  1. Open an **issue**.
  2. Create a **branch from `dev`**, named `<type>/<issue#>-<slug>` (e.g., `lab/5-hpc-pocket-cluster`, `docs/2-repo-foundations`).
  3. Open a **draft PR into `dev`** referencing the issue (`Closes #N`).
  4. Mark ready for review, then merge into `dev`.
  5. Periodically merge `dev` into `main` at milestones.

## 6. Future Roadmap

- A global `irk` command-line wrapper to manage labs (e.g., `irk lab start pocket-cluster`).
- Pre-commit hooks to validate Bash syntax and Markdown linting.
- Automated sync of `docs/` to the GitHub wiki.
