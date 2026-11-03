#!/usr/bin/env bash
# fault-status - are you done with the troubleshooting exercise on this node?
#
#   fault-status            check whether the planted problem is fixed
#   fault-status --ticket   show the ticket (the user's complaint) again
#
# Exit code: 0 = fixed, 1 = not fixed yet, 2 = no exercise is active.
set -u

case "${1:-}" in -h|--help) sed -n '2,7p' "$0"; exit 0 ;; esac

TOOL=/usr/local/bin/inject-fault
[ -x "$TOOL" ] || { echo "fault-status: $TOOL not found. Run: vagrant provision" >&2; exit 2; }

case "${1:-}" in
  --ticket)  [ "$(id -u)" -eq 0 ] && exec "$TOOL" --ticket || exec sudo "$TOOL" --ticket ;;
  "")        ;;
  *)         echo "fault-status: unknown option '$1' (see --help)" >&2; exit 2 ;;
esac

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"

$SUDO "$TOOL" --check
rc=$?

case "$rc" in
  0) echo
     echo "Before you move on, write your note for the ticket:"
     echo "  1. what the user reported       3. the root cause"
     echo "  2. what you checked, in order   4. what you changed to fix it"
     ;;
  1) echo "Need the details again? Run: fault-status --ticket"
     ;;
esac
exit "$rc"
