#!/usr/bin/env bash
# down.sh - stop the lab, or delete it completely.
#
#   ./down.sh            stop every node (disks are kept; ./up.sh starts them again)
#   ./down.sh --destroy  delete every node and its disk
#
set -euo pipefail

case "${1:-}" in
  -h|--help) sed -n '2,6p' "$0"; exit 0 ;;
  --destroy) action=(destroy -f) ;;
  "")        action=(halt) ;;
  *)         echo "down.sh: unknown option '$1' (see --help)" >&2; exit 2 ;;
esac

cd "$(dirname "$0")"
command -v vagrant >/dev/null 2>&1 || { echo "down.sh: vagrant is not installed" >&2; exit 1; }
exec vagrant "${action[@]}"
