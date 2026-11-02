# IRK (Infrastructure Run Kit) Specification

## 1. Vision & Purpose
**IRK** is a unified toolkit and sandbox environment designed for HPC and AI infrastructure engineers. It bridges the gap between daily operational support tasks and experimental development. 

The repository serves two main functions:
1. **Support Tools:** A centralized bin of scripts and utilities for cluster telemetry, node debugging, and daily operations.
2. **Lab Environments:** A collection of isolated, reproducible virtual environments (e.g., multi-node Vagrant setups) used to simulate, benchmark, and test infrastructure changes before deploying to bare-metal hardware.

## 2. Directory Architecture

```text
irk/
├── bin/                 # Executable operational CLI tools (add to $PATH)
├── support/             # Domain-specific helpers, telemetry, and diagnostic scripts
│   ├── cluster/         # Slurm, Node states, job orchestration
│   ├── gpu/             # DCGM, NVIDIA bindings, CUDA validations
│   └── storage/         # I/O benchmarking and filesystem checks
├── labs/                # Reproducible sandbox environments
│   └── template/        # Boilerplate for creating a new lab
├── CLAUDE.md            # AI interaction guidelines
├── SPEC.md              # Project specification and architecture
└── README.md            # Main entry point and quickstart
```

## 3. Lab Specification

Every environment added to the labs/ directory MUST adhere to the following structure to ensure it remains modular and understandable:

    Self-Contained: A lab should not depend on files outside its specific directory (except global bin/ tools where documented).

    Required Files:

        README.md: Must clearly state the lab's purpose, architecture (e.g., 1 login node, 2 compute nodes), and OS/RAM constraints.

        up.sh / down.sh: (Optional but recommended) wrapper scripts for bringing the lab online/offline (e.g., wrapping vagrant up).

        Configuration Files: Vagrantfile, docker-compose.yml, or hosts.ini.

## 4. Execution Model

    bin/ Tooling: Scripts placed in bin/ are designed to be executed directly by the user on live clusters or local machines. Users should consider adding irk/bin to their .bashrc/.zshrc $PATH.

    Naming Conventions: Script names should be hyphenated, lowercase, and descriptive (e.g., node-drain, gpu-health-check).

## 5. Future Roadmap

    Develop a global irk command-line wrapper to manage labs (e.g., irk lab start pocket-cluster).

    Integrate pre-commit hooks to validate bash script syntax and markdown linting.