# Lab Guide

Labs in `labs/` are isolated, reproducible environments to simulate, benchmark, and test infrastructure changes before bare-metal deployment.

## Requirements
- **Self-contained:** no dependency on files outside the lab directory, except documented `bin/` tools.
- **Declarative:** prefer Vagrantfiles, Ansible playbooks, and compose files over manual shell steps.
- **Lightweight:** default to about 1 GB RAM per VM unless the lab states otherwise. Measure before you go lower, and state the measured limit in the lab's README.
- **Naming:** lowercase, hyphenated (`hpc-pocket-cluster`).

## Required files
| File | Purpose |
|------|---------|
| `README.md` | Purpose, architecture (e.g., 1 login + 2 compute nodes), OS/RAM constraints, usage |
| `Vagrantfile` / `docker-compose.yml` / `hosts.ini` | The environment definition |
| `up.sh`, `down.sh` | Recommended wrappers (e.g., around `vagrant up` / `vagrant destroy`) |

## Adding a lab
1. Open an issue ([workflow](Development-Workflow)).
2. Branch `lab/<issue#>-<name>` from `dev`.
3. Copy `labs/template/` to `labs/<name>/` and fill it in.
4. Add a page or entry for the lab in `docs/` and link it from [Home](Home).
5. Open a draft PR into `dev`.

## Modular labs
A lab with several topics can be split into a small `core/` (applied to every node) plus `modules/NN-<name>/`. Each module has its own `README.md`, an optional `bin/` of tools (installed on every node) and an optional `provision.sh` run on demand. The Vagrantfile only describes the machines. [hpc-training-cluster](#existing-labs) is the reference example.

## Existing labs
| Lab | What it is | Nodes | RAM per node |
|-----|-----------|-------|--------------|
| [hpc-training-cluster](https://github.com/AhmedYousriSobhi/IRK/tree/main/labs/hpc-training-cluster) | Self-paced tutorial cluster (Rocky Linux 9) with troubleshooting exercises, Slurm and health checks. Start at its README. | 1 login + 2 compute (1 to 9 configurable) | 1 GB (`LAB_MEM_MB` changes it) |
