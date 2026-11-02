# IRK (Infrastructure Run Kit)

**IRK** is a toolkit and sandbox for HPC and AI infrastructure engineers. It bridges daily operational support and experimental lab work: the same repo holds the scripts you run on live clusters and the reproducible environments you use to test changes before they reach bare metal.

| Part | What it is |
|------|------------|
| **Support tools** (`bin/`, `support/`) | Zero-dependency Bash/Python utilities for cluster telemetry, node debugging, and daily operations (Slurm, NVIDIA DCGM, CUDA, storage). |
| **Labs** (`labs/`) | Isolated, self-contained, reproducible environments (Vagrant, Ansible, Docker) that simulate multi-node clusters, benchmark, and test infrastructure changes. |

> **Status:** early stage. The structure below is the target layout; directories appear as features land. See the [roadmap](SPEC.md#6-future-roadmap).

## Repository Structure

```text
irk/
├── bin/          # Executable CLI tools (add to $PATH)
├── support/      # Domain helpers: cluster/, gpu/, storage/
├── labs/         # Self-contained sandbox environments
│   └── template/ # Boilerplate for a new lab
├── docs/         # Local wiki (mirrors the GitHub wiki)
├── CLAUDE.md     # AI assistant rules
├── SPEC.md       # Architecture and repository rules
└── README.md     # You are here
```

## Getting Started

Clone the repo and put `bin/` on your `$PATH`:

```bash
git clone git@github.com:AhmedYousriSobhi/IRK.git ~/.irk

# Add to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.irk/bin:$PATH"
```

Every script in `bin/` supports `--help`.

## Labs

Each lab lives in `labs/<name>/` with its own `README.md` stating its purpose, topology, and OS/RAM requirements. Typical usage:

```bash
cd labs/<lab-name>
./up.sh      # or: vagrant up
./down.sh    # or: vagrant destroy
```

Labs default to lightweight VMs (about 1 GB RAM each). Check the lab's README before starting one.

## Principles

- **Zero dependency:** `bin/` and `support/` use standard Bash or Python 3 only.
- **Safe by default:** Bash scripts use `set -euo pipefail`; operational scripts are idempotent.
- **Self-contained labs:** a lab never depends on files outside its own directory (except documented `bin/` tools).

## Documentation and Contributing

- Documentation lives in [`docs/`](docs/Home.md) and is mirrored to the [GitHub wiki](https://github.com/AhmedYousriSobhi/IRK/wiki).
- Work follows **issue → branch → draft PR into `dev`**; `dev` is merged to `main` at milestones. See [Development Workflow](docs/Development-Workflow.md).
- Architecture and rules: [SPEC.md](SPEC.md).
