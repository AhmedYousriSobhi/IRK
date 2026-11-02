# Lab Guide

Labs in `labs/` are isolated, reproducible environments to simulate, benchmark, and test infrastructure changes before bare-metal deployment.

## Requirements
- **Self-contained:** no dependency on files outside the lab directory, except documented `bin/` tools.
- **Declarative:** prefer Vagrantfiles, Ansible playbooks, and compose files over manual shell steps.
- **Lightweight:** default to about 1 GB RAM per VM unless the lab states otherwise.
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
3. Copy `labs/template/` to `labs/<name>/` and fill it in. The template holds a README skeleton, a small parameterised Vagrantfile (N nodes, RAM, CPUs, network and VM-name prefix as `LAB_*` variables), and `up.sh` / `down.sh` wrappers with `--help`.
4. Add a page or entry for the lab in `docs/` and link it from [Home](Home).
5. Open a draft PR into `dev`.
