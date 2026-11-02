# Coding Standards

## Scripts (`bin/`, `support/`)
- Pure Bash (`#!/usr/bin/env bash`) or standard Python 3.
- **Zero dependencies:** avoid third-party libraries unless absolutely necessary.
- **Safety:** Bash scripts start with `set -euo pipefail`.
- **Idempotency:** safe to run repeatedly, with no duplicated configuration or destructive overwrites.
- Executables in `bin/` provide `--help` / `-h` describing usage and required flags.

## Documentation
- Clean, standard Markdown; empirical and structural explanations.
- Diagrams and trees use fenced `text` or `mermaid` blocks.

## Hygiene
- Never commit secrets, logs, benchmark output, or VM artifacts; `.gitignore` covers the common cases.
