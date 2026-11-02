#!/usr/bin/env bash
# slurm-verify - check the Slurm build on this node.
#
#   slurm-verify        run the checks (run it on the login node and on each compute node)
#
# On the login node it also runs a small test job on every compute node.
# Cross-node checks (munge across nodes, identical slurm.conf) need SSH keys between the nodes
# (a chapter 3 exercise); without them those checks are skipped, not failed.
# Run it as your normal user; it uses sudo -n for the few checks that need root.
# Exit code: 0 = no failures (warnings allowed), 1 = at least one check failed.
set -u

RELEASE_FILE="${LAB_RELEASE_FILE:-/etc/hpc-lab-release}"
CONF="${SLURM_CONF:-/etc/slurm/slurm.conf}"
EXPECT_SLURM_UID=2200
EXPECT_MUNGE_UID=2201
case "${1:-}" in -h|--help) sed -n '2,10p' "$0"; exit 0 ;; esac

pass=0; warn=0; fail=0
ok()   { printf '[PASS] %-20s %s\n' "$1" "$2"; pass=$((pass+1)); }
bad()  { printf '[FAIL] %-20s %s\n' "$1" "$2"; [ -n "${3:-}" ] && printf '       -> %s\n' "$3"; fail=$((fail+1)); }
note() { printf '[WARN] %-20s %s\n' "$1" "$2"; [ -n "${3:-}" ] && printf '       -> %s\n' "$3"; warn=$((warn+1)); }
info() { printf '[INFO] %-20s %s\n' "$1" "$2"; }

if [ ! -r "$RELEASE_FILE" ]; then
  echo "slurm-verify: $RELEASE_FILE not found; this is not a provisioned lab node." >&2; exit 1
fi
# shellcheck disable=SC1090
. "$RELEASE_FILE"

ROOT=""
if [ "$(id -u)" -ne 0 ]; then
  if sudo -n true 2>/dev/null; then ROOT="sudo -n"; else ROOT="NONE"; fi
fi
as_root() { if [ "$ROOT" = NONE ]; then return 99; fi; $ROOT "$@"; }

conf_val() { grep -E "^[[:space:]]*$1=" "$CONF" 2>/dev/null | tail -1 | cut -d= -f2- | tr -d '[:space:]'; }
owner_of() { stat -c '%U' "$1" 2>/dev/null; }

computes=()
IFS=',' read -ra pairs <<< "$LAB_NODES"
for p in "${pairs[@]}"; do case "${p%%=*}" in compute*) computes+=("${p%%=*}") ;; esac; done

echo "Node: $LAB_NODE ($LAB_ROLE)"; echo

# ---- accounts ---------------------------------------------------------------
for spec in "slurm:$EXPECT_SLURM_UID" "munge:$EXPECT_MUNGE_UID"; do
  u="${spec%%:*}"; want="${spec##*:}"; got="$(id -u "$u" 2>/dev/null || echo missing)"
  if [ "$got" = "$want" ]; then ok "Account $u" "uid $got"
  else bad "Account $u" "uid is $got, expected $want" "IDs must match on every node. Run: vagrant provision --provision-with stage-clean,stage,stage-modules,slurm"; fi
done

# ---- munge ------------------------------------------------------------------
if systemctl is-active --quiet munge 2>/dev/null; then ok "munge service" "running"
else bad "munge service" "not running" "sudo systemctl enable --now munge, then read: journalctl -u munge -n 20"; fi
if ! systemctl is-enabled --quiet munge 2>/dev/null; then note "munge enabled" "will not start after a reboot" "sudo systemctl enable munge"; fi
if munge -n 2>/dev/null | unmunge 2>/dev/null | grep -q 'STATUS:.*Success'; then ok "munge round trip" "credential encoded and decoded"
else bad "munge round trip" "munge -n | unmunge failed" "Is munge running? Is the key readable only by munge (mode 400)? Does the clock agree?"; fi
keyinfo="$(as_root stat -c '%a %U:%G' /etc/munge/munge.key 2>/dev/null)"
if [ -z "$keyinfo" ]; then info "munge key" "mode could not be read (run with sudo access for this check)"
elif [ "$keyinfo" = "400 munge:munge" ]; then ok "munge key" "mode 400, owned by munge"
else bad "munge key" "is '$keyinfo', expected '400 munge:munge'" "sudo chown munge:munge /etc/munge/munge.key; sudo chmod 400 /etc/munge/munge.key"; fi
fp="$(as_root sha256sum /etc/munge/munge.key 2>/dev/null | cut -c1-12)"
[ -n "$fp" ] && info "munge key" "fingerprint $fp (identical on every node)"

# ---- clock ------------------------------------------------------------------
if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ]; then ok "Clock" "synchronized"
else note "Clock" "not synchronized" "munge rejects credentials when clocks differ. Run: lab-verify --fix"; fi

# ---- slurm.conf -------------------------------------------------------------
if [ -r "$CONF" ]; then
  ok "slurm.conf" "found at $CONF"
  if grep -v '^[[:space:]]*#' "$CONF" | grep -q 'CHANGE_ME'; then bad "slurm.conf" "still contains CHANGE_ME" "Run 'slurmd -C' on a compute node and put the RealMemory value in the NodeName lines."; fi
  cluster="$(conf_val ClusterName)"; [ -n "$cluster" ] && info "slurm.conf" "ClusterName=$cluster"
else
  bad "slurm.conf" "$CONF is missing or unreadable" "Copy /shared/slurm-lab/slurm.conf.template to $CONF after editing it."
fi

dir_check() {  # dir_check <label> <path> <owner>
  local d="$2"
  if [ -z "$d" ]; then bad "$1" "not set in slurm.conf"; return; fi
  if [ ! -d "$d" ]; then bad "$1" "$d does not exist" "sudo mkdir -p $d; sudo chown slurm:slurm $d"; return; fi
  if [ "$(owner_of "$d")" = "$3" ]; then ok "$1" "$d owned by $3"
  else bad "$1" "$d is owned by $(owner_of "$d"), expected $3" "sudo chown $3:$3 $d"; fi
}
if [ -r "$CONF" ]; then
  if [ "$LAB_ROLE" = login ]; then
    dir_check "State directory" "$(conf_val StateSaveLocation)" slurm
    dir_check "Log directory" "$(dirname "$(conf_val SlurmctldLogFile)")" slurm
  else
    dir_check "Spool directory" "$(conf_val SlurmdSpoolDir)" root
    dir_check "Log directory" "$(dirname "$(conf_val SlurmdLogFile)")" slurm
  fi
fi

# ---- daemons ----------------------------------------------------------------
if [ "$LAB_ROLE" = login ]; then svc=slurmctld; log=$(conf_val SlurmctldLogFile); else svc=slurmd; log=$(conf_val SlurmdLogFile); fi
if systemctl is-active --quiet "$svc" 2>/dev/null; then ok "$svc service" "running"
else bad "$svc service" "not running" "journalctl -u $svc -n 30   and   tail -n 30 ${log:-/var/log/slurm/$svc.log}"; fi
if ! systemctl is-enabled --quiet "$svc" 2>/dev/null; then note "$svc enabled" "will not start after a reboot" "sudo systemctl enable $svc"; fi

if command -v scontrol >/dev/null 2>&1; then
  if timeout 15 scontrol ping 2>/dev/null | grep -qi 'is UP'; then ok "Controller" "reachable (scontrol ping)"
  else bad "Controller" "scontrol ping cannot reach slurmctld" "Is slurmctld running on login? Same slurm.conf and munge key on this node? Is the clock right?"; fi
else
  bad "Slurm client" "scontrol not found" "Install the Slurm packages for this node (dnf search slurm)."
fi

if [ "$LAB_ROLE" = compute ] && command -v slurmd >/dev/null 2>&1 && [ -r "$CONF" ]; then
  real="$(slurmd -C 2>/dev/null | grep -o 'RealMemory=[0-9]*' | head -1 | cut -d= -f2)"
  want="$(grep -E "^NodeName=$LAB_NODE([[:space:]]|\$)" "$CONF" | grep -o 'RealMemory=[0-9]*' | head -1 | cut -d= -f2)"
  if [ -z "$real" ] || [ -z "$want" ]; then info "RealMemory" "could not compare (slurmd -C or the NodeName line for $LAB_NODE is missing)"
  elif [ "$want" -gt "$real" ]; then bad "RealMemory" "slurm.conf says $want MB but this node has $real MB" "Slurm will mark the node invalid or drained. Set RealMemory to $real or less."
  else ok "RealMemory" "configured $want MB, node reports $real MB"; fi
fi

# ---- cluster view and test job (login node) ---------------------------------
if [ "$LAB_ROLE" = login ] && command -v sinfo >/dev/null 2>&1; then
  states="$(timeout 20 sinfo -h -N -o '%N %t' 2>/dev/null)"
  if [ -z "$states" ]; then bad "Nodes" "sinfo shows nothing" "Check slurmctld, and that the NodeName/PartitionName lines in slurm.conf are correct."
  else
    for n in "${computes[@]}"; do
      st="$(echo "$states" | awk -v n="$n" '$1==n {print $2; exit}')"
      case "$st" in
        idle|mix|alloc|comp) ok "Node $n" "state $st" ;;
        "") bad "Node $n" "not listed by sinfo" "Is it in the NodeName and PartitionName lines of slurm.conf?" ;;
        *)  bad "Node $n" "state '$st'" "Check slurmd on $n. See why with: scontrol show node $n | grep -i reason" ;;
      esac
    done
  fi
  if [ "${#computes[@]}" -gt 0 ]; then
    n="${#computes[@]}"
    out="$(timeout 120 srun -N "$n" -n "$n" hostname 2>&1)"; rc=$?
    got="$(echo "$out" | sort | tr '\n' ' ')"; want="$(printf '%s\n' "${computes[@]}" | sort | tr '\n' ' ')"
    if [ $rc -eq 0 ] && [ "$got" = "$want" ]; then ok "Test job" "srun ran on: $got"
    else bad "Test job" "srun -N $n hostname failed (exit $rc): $(echo "$out" | head -2 | tr '\n' ' ')" "Check the node states above, then: squeue; scontrol show job; and the slurmd logs on the compute nodes."; fi
  fi
else
  [ "$LAB_ROLE" = compute ] && info "Test job" "run slurm-verify on the login node for the cluster-wide test job"
fi

# ---- cross-node checks (need SSH keys between nodes) ------------------------
SSH="ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new"
cross_done=0
for p in "${pairs[@]}"; do
  peer="${p%%=*}"; [ "$peer" = "$LAB_NODE" ] && continue
  if ! $SSH "$peer" true 2>/dev/null; then
    [ "$cross_done" -eq 0 ] && info "Cross-node checks" "skipped: no SSH key access to $peer (set up SSH keys between nodes first)"
    break
  fi
  cross_done=1
  if munge -n 2>/dev/null | $SSH "$peer" unmunge 2>/dev/null | grep -q 'STATUS:.*Success'; then ok "munge to $peer" "credential accepted"
  else bad "munge to $peer" "$peer rejected a credential from this node" "Different key, different clock, or munge not running on $peer."; fi
  mine="$(md5sum "$CONF" 2>/dev/null | cut -d' ' -f1)"; theirs="$($SSH "$peer" md5sum "$CONF" 2>/dev/null | cut -d' ' -f1)"
  if [ -n "$mine" ] && [ "$mine" = "$theirs" ]; then ok "slurm.conf on $peer" "identical"
  else bad "slurm.conf on $peer" "differs from this node (or is missing)" "slurm.conf must be identical on every node."; fi
done

echo
echo "Summary: $pass passed, $warn warnings, $fail failed"
if [ "$fail" -gt 0 ]; then echo "Result: NOT READY"; exit 1; fi
echo "Result: SLURM LOOKS HEALTHY"; exit 0
