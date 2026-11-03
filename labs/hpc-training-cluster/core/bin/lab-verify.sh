#!/usr/bin/env bash
# lab-verify - health check for an HPC lab node.
#
#   lab-verify          run the checks on this node
#   lab-verify --fix    also try the safe fixes (resync the clock, remount /shared)
#
# Run it on every node:  vagrant ssh login -c lab-verify
# Exit code: 0 = all good (warnings allowed), 1 = at least one check failed.
# No -e or pipefail on purpose: every check must run even when an earlier one fails.
set -u

RELEASE_FILE="${LAB_RELEASE_FILE:-/etc/hpc-lab-release}"
FIX=0
[ "${1:-}" = "--fix" ] && FIX=1
case "${1:-}" in -h|--help) sed -n '2,8p' "$0"; exit 0 ;; esac

pass=0; warn=0; fail=0
ok()   { printf '[PASS] %-18s %s\n' "$1" "$2"; pass=$((pass+1)); }
bad()  { printf '[FAIL] %-18s %s\n' "$1" "$2"; [ -n "${3:-}" ] && printf '       -> %s\n' "$3"; fail=$((fail+1)); }
note() { printf '[WARN] %-18s %s\n' "$1" "$2"; [ -n "${3:-}" ] && printf '       -> %s\n' "$3"; warn=$((warn+1)); }
SUDO=""; [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1 && SUDO="sudo -n"

if [ ! -r "$RELEASE_FILE" ]; then
  bad "Lab setup" "$RELEASE_FILE not found" "This node was not provisioned. Run: vagrant provision <node>"
  echo; echo "Result: FAILED"; exit 1
fi
# shellcheck disable=SC1090
. "$RELEASE_FILE"
echo "Node: $LAB_NODE ($LAB_ROLE, $LAB_IP), provisioned $LAB_PROVISIONED"
echo

# ---- identity and name resolution -------------------------------------------
if [ "$(hostname -s)" = "$LAB_NODE" ]; then ok "Hostname" "$LAB_NODE"
else bad "Hostname" "is $(hostname -s), expected $LAB_NODE" "sudo hostnamectl set-hostname $LAB_NODE"; fi

IFS=',' read -ra pairs <<< "$LAB_NODES"
for p in "${pairs[@]}"; do
  name="${p%%=*}"; ip="${p#*=}"
  got="$(getent hosts "$name" | awk '{print $1; exit}')"
  if [ "$got" = "$ip" ]; then
    if ping -c1 -W2 "$ip" >/dev/null 2>&1; then ok "Node $name" "$ip resolves and answers ping"
    elif [ "$name" = "$LAB_NODE" ]; then ok "Node $name" "$ip (this node)"
    else bad "Node $name" "$ip resolves but does not answer ping" "Is that VM running? Check: vagrant status"; fi
  else
    bad "Node $name" "resolves to '${got:-nothing}', expected $ip" "Re-run provisioning: vagrant provision"
  fi
done

# ---- clock ------------------------------------------------------------------
sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
if [ "$sync" = "yes" ]; then ok "Clock" "synchronized"
else
  if [ "$FIX" -eq 1 ]; then
    $SUDO systemctl restart chronyd >/dev/null 2>&1; $SUDO chronyc makestep >/dev/null 2>&1
    # chrony needs several seconds to pick a source again; wait up to 20 s
    for _ in $(seq 1 10); do
      sleep 2
      sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
      [ "$sync" = "yes" ] && break
    done
  fi
  if [ "$sync" = "yes" ]; then ok "Clock" "synchronized (after fix)"
  else note "Clock" "not synchronized" "Run: lab-verify --fix. A laptop that slept leaves VM clocks wrong, which breaks cluster authentication later."; fi
fi

# ---- shared storage ---------------------------------------------------------
if [ "$LAB_ROLE" = "login" ]; then
  if systemctl is-active --quiet nfs-server 2>/dev/null; then ok "NFS server" "running"
  else bad "NFS server" "not running" "sudo systemctl enable --now nfs-server"; fi
  if $SUDO exportfs -v 2>/dev/null | grep -q "$LAB_SHARED"; then ok "NFS export" "$LAB_SHARED exported"
  else note "NFS export" "could not confirm $LAB_SHARED is exported" "Check as root: sudo exportfs -v"; fi
else
  if ! findmnt -n -t nfs,nfs4 "$LAB_SHARED" >/dev/null 2>&1 && [ "$FIX" -eq 1 ]; then
    $SUDO mount "$LAB_SHARED" >/dev/null 2>&1
  fi
  if findmnt -n -t nfs,nfs4 "$LAB_SHARED" >/dev/null 2>&1; then ok "NFS mount" "$LAB_SHARED mounted"
  else bad "NFS mount" "$LAB_SHARED is not mounted" "Run: lab-verify --fix (needs the login node to be up)"; fi
fi
probe="$LAB_SHARED/scratch/.verify-$LAB_NODE"
if touch "$probe" 2>/dev/null; then
  ok "Shared write" "wrote $probe"
  seen="$(ls -A "$LAB_SHARED/scratch" 2>/dev/null | grep -c '^\.verify-')"
  echo "       (nodes that have written a verify file so far: $seen)"
else bad "Shared write" "cannot write to $LAB_SHARED/scratch" "Check the NFS mount and permissions on $LAB_SHARED/scratch"; fi

# ---- accounts ---------------------------------------------------------------
IFS=',' read -ra users <<< "$LAB_USERS"
for e in "${users[@]}"; do
  u="${e%%:*}"; uid="${e##*:}"
  got="$(id -u "$u" 2>/dev/null || echo missing)"
  if [ "$got" = "$uid" ]; then ok "User $u" "uid $uid"
  else bad "User $u" "uid is $got, expected $uid" "Re-run provisioning: vagrant provision"; fi
done

# ---- platform settings (informational) -------------------------------------
if command -v getenforce >/dev/null 2>&1; then
  mode="$(getenforce)"
  if [ "$mode" = "Disabled" ] || [ "$(getsebool use_nfs_home_dirs 2>/dev/null | awk '{print $NF}')" = "on" ]; then
    ok "SELinux" "$mode, NFS home directories allowed"
  else note "SELinux" "$mode but use_nfs_home_dirs is off" "sudo setsebool -P use_nfs_home_dirs 1"; fi
fi
if [ -n "$(swapon --show --noheadings 2>/dev/null)" ]; then ok "Swap" "enabled"
else note "Swap" "no swap configured" "1 GB nodes can run out of memory during installs. Re-run provisioning: vagrant provision"; fi
free_gb=$(( $(df -P / | awk 'NR==2 {print $4}') / 1024 / 1024 ))
if [ "$free_gb" -ge 2 ]; then ok "Disk (/)" "${free_gb} GiB free"
else note "Disk (/)" "only ${free_gb} GiB free" "Free some space before installing software"; fi

echo
echo "Summary: $pass passed, $warn warnings, $fail failed"
if [ "$fail" -gt 0 ]; then echo "Result: NOT HEALTHY"; exit 1; fi
echo "Result: HEALTHY"; exit 0
