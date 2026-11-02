# Repository Structure

```text
irk/
├── bin/                 # Executable operational CLI tools (add to $PATH)
├── support/             # Domain-specific helpers, telemetry, diagnostics
│   ├── cluster/         # Slurm, node states, job orchestration
│   ├── gpu/             # DCGM, NVIDIA bindings, CUDA validations
│   └── storage/         # I/O benchmarking and filesystem checks
├── labs/                # Reproducible sandbox environments
│   └── template/        # Boilerplate for a new lab
├── docs/                # Local wiki (mirrors the GitHub wiki)
├── .github/             # PR template
├── CLAUDE.md            # AI assistant rules
├── SPEC.md              # Architecture and repository rules
└── README.md
```

Directories are created when the first feature needs them.

## Where does a script go?
| Script is... | Location |
|--------------|----------|
| A daily CLI tool used on live clusters or local machines | `bin/` |
| A reusable helper/diagnostic grouped by domain | `support/<domain>/` |
| Specific to one lab environment | `labs/<name>/` |

Naming: hyphenated, lowercase, descriptive (`node-drain`, `gpu-health-check`).

Add `bin/` to your `$PATH`:

```bash
export PATH="$HOME/.irk/bin:$PATH"
```
