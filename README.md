# IRK (Infrastructure Run Kit)

**IRK** is a unified toolkit and sandbox environment designed for High-Performance Computing (HPC) and AI infrastructure engineering. 

It serves two primary functions:
1. **Operational Support:** A centralized collection of zero-dependency daily utilities, cluster telemetry scripts, and diagnostic tools.
2. **Reproducible Labs:** A collection of isolated, contained virtual environments (using tools like Vagrant) to simulate multi-node clusters, benchmark storage, and test orchestration setups locally before bare-metal deployment.

## Repository Structure

```text
irk/
├── bin/                 # Executable CLI tools intended for your $PATH
├── support/             # Domain-specific helpers (Slurm, DCGM, storage checks)
├── labs/                # Self-contained sandbox environments
│   └── template/        # Boilerplate for bootstrapping new labs
├── CLAUDE.md            # AI interaction guidelines and coding standards
└── SPEC.md              # Technical architecture and repository rules

Getting Started

To use the daily operational tools globally on your machine, clone the repository and add the bin/ directory to your $PATH.
Bash

git clone [https://github.com/yourusername/irk.git](https://github.com/yourusername/irk.git) ~/.irk

# Add to your .bashrc or .zshrc
export PATH="$HOME/.irk/bin:$PATH"

Labs

The labs/ directory contains localized virtual environments for experimenting with infrastructure components (e.g., Slurm scheduling, GPU telemetry, container orchestration).

Every lab is completely self-contained with its own README.md and configuration files (Vagrant, Ansible, etc.).

Example Workflow:
Bash

cd labs/hpc-pocket-cluster
vagrant up
vagrant ssh login-node

Note: Check the README.md inside each specific lab directory for hardware requirements (e.g., memory constraints per node) and setup instructions.
Guidelines

    Zero-Dependency: Scripts in bin/ and support/ should rely on standard Bash/Python built-ins wherever possible to ensure portability across different cluster environments.

    Idempotency: Operational and provisioning scripts are designed to be safe to run multiple times.

    Modularity: Keep lab dependencies contained within their respective labs/<name> directory.

For detailed architectural guidelines and contribution rules, refer to SPEC.md.