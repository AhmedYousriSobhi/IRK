#!/usr/bin/env bash
# up.sh - build (or start) the lab. A thin wrapper around 'vagrant up'.
#
#   ./up.sh                      start every node with the detected provider
#   ./up.sh --provider=libvirt   choose the provider (passed to vagrant up)
#   ./up.sh node1                start one node
#
# Settings are environment variables; see the top of the Vagrantfile.
set -euo pipefail

case "${1:-}" in -h|--help) sed -n '2,8p' "$0"; exit 0 ;; esac

cd "$(dirname "$0")"
command -v vagrant >/dev/null 2>&1 || { echo "up.sh: vagrant is not installed" >&2; exit 1; }
exec vagrant up "$@"
