# AI Assistant Instructions for IRK (Infrastructure Run Kit)

IRK is a repository of operational support scripts, telemetry tools, and reproducible lab environments for HPC and AI infrastructure engineering. Full details live in the docs; this file holds only the rules the assistant must follow.

## Source of Truth
- Architecture and repo rules: [SPEC.md](SPEC.md). Do not modify it unless explicitly instructed.
- Everything else is documented in [docs/](docs/Home.md) (the local wiki, mirrored to the GitHub wiki):
  - [Repository Structure](docs/Repository-Structure.md)
  - [Coding Standards](docs/Coding-Standards.md)
  - [Lab Guide](docs/Lab-Guide.md)
  - [Development Workflow](docs/Development-Workflow.md)
- Do not duplicate documentation here. Update `docs/` instead.

## Workflow Rules
- For every feature/modification/fix: open an issue, branch from `dev` (`<type>/<issue#>-<slug>`), open a **draft PR into `dev`**. Never commit directly to `dev` or `main`; `dev` is merged to `main` only at milestones.
- Keep `docs/` (and `README.md` when user-facing) updated in the same PR as the change.
- New lab: always include a local `README.md`. New script: decide between `bin/` (daily CLI) and a specific `labs/<name>/` (environment-specific).
- Commits: use the repo's configured GitHub noreply email; no attribution lines in commits or PR descriptions.
- Confirm before force-pushes, deleting branches, or anything affecting the remote beyond the current issue's branch.

## Quick Standards (details in docs/Coding-Standards.md)
- Bash: `#!/usr/bin/env bash`, `set -euo pipefail`, idempotent, `--help` for `bin/` tools. Python: standard library only unless unavoidable.
- Labs: self-contained, declarative, about 1 GB RAM per VM by default.
- Never commit secrets, logs, or VM artifacts (see `.gitignore`).
