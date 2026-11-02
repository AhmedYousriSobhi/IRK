#!/usr/bin/env bash
# provision.sh (module 03-slurm) - get a lab node ready for the "install and configure Slurm" chapter.
#
# Run on every node, login node first (the compute nodes fetch the munge key from it):
#   vagrant provision --provision-with stage-clean,stage,stage-modules,slurm
#
# What it does (it does NOT install or start Slurm; the learner does that):
#   - enables the extra repositories Slurm needs (EPEL, CRB) and reports which Slurm packages exist
#   - creates the 'slurm' and 'munge' accounts with the same IDs on every node
#   - installs munge and puts the SAME munge key on every node (not started)
#   - login node: writes a slurm.conf template and a step-by-step checklist to /shared/slurm-lab/
#   - reports clock, name resolution and key checks
#
# Options (or the same names as environment variables on the host running vagrant):
#   --no-key   SLURM_NO_KEY=1   do not place the munge key on compute nodes
#                               (the learner copies it, which needs the SSH keys from chapter 3)
#   --clean    SLURM_CLEAN=1    remove the staged key and template from /shared/slurm-lab (login node)
#
# Safe to run more than once.
set -euo pipefail

RELEASE_FILE="${LAB_RELEASE_FILE:-/etc/hpc-lab-release}"
NO_KEY="${SLURM_NO_KEY:-0}"
CLEAN="${SLURM_CLEAN:-0}"
for arg in "$@"; do
  case "$arg" in
    --no-key) NO_KEY=1 ;;
    --clean)  CLEAN=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "slurm provision: unknown option '$arg' (see --help)" >&2; exit 2 ;;
  esac
done

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO (command: $BASH_COMMAND)"' ERR

[ "$(id -u)" -eq 0 ] || die "run as root"
[ -r "$RELEASE_FILE" ] || die "$RELEASE_FILE not found: run the base provisioning first (vagrant provision --provision-with base)"
# shellcheck disable=SC1090
. "$RELEASE_FILE"
STAGE="$LAB_SHARED/slurm-lab"
MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SLURM_UID=2200
MUNGE_UID=2201

# ---- cleanup mode -------------------------------------------------------------
if [ "$CLEAN" = "1" ]; then
  [ "$LAB_ROLE" = "login" ] || die "--clean runs on the login node (the staged files are owned there)"
  rm -rf "$STAGE"
  log "removed $STAGE (staged munge key and template)"
  exit 0
fi

log "preparing $LAB_NODE ($LAB_ROLE) for the Slurm chapter"

# ---- this module's tools (slurm-verify, why-pending) ---------------------------
# provision-base installs these too; doing it here makes the module work on its own.
for f in "$MODULE_DIR"/bin/*; do
  [ -f "$f" ] && install -m 0755 "$f" "/usr/local/bin/$(basename "${f%.sh}")"
done

# ---- repositories -------------------------------------------------------------
dnf -y install dnf-plugins-core >/dev/null
dnf config-manager --set-enabled crb >/dev/null 2>&1 || warn "could not enable the CRB repository (continuing)"
dnf -y --setopt=install_weak_deps=False install epel-release >/dev/null 2>&1 || warn "could not enable EPEL, where the Slurm packages live (continuing)"
dnf -y makecache >/dev/null 2>&1 || warn "could not refresh package metadata"
avail="$(dnf -q repoquery --qf '%{name}-%{version}' slurm slurm-slurmctld slurm-slurmd 2>/dev/null | sort -u | tr '\n' ' ')"
if [ -n "$avail" ]; then
  log "Slurm packages available: $avail"
else
  warn "no Slurm packages found in the enabled repositories. Slurm comes from EPEL: check that the node can reach the internet and run: dnf repolist"
fi

# ---- accounts with identical IDs on every node --------------------------------
getent group slurm >/dev/null || groupadd -g "$SLURM_UID" slurm
id -u slurm >/dev/null 2>&1 || useradd -u "$SLURM_UID" -g slurm -M -s /sbin/nologin -d /var/lib/slurm -c "Slurm workload manager" slurm
getent group munge >/dev/null || groupadd -g "$MUNGE_UID" munge
id -u munge >/dev/null 2>&1 || useradd -u "$MUNGE_UID" -g munge -M -s /sbin/nologin -d /var/lib/munge -c "MUNGE authentication" munge
log "accounts: slurm (uid $(id -u slurm)), munge (uid $(id -u munge))"

# ---- munge: installed, same key everywhere, not started -----------------------
dnf -y --setopt=install_weak_deps=False install munge munge-libs >/dev/null
KEY=/etc/munge/munge.key

if [ "$LAB_ROLE" = "login" ]; then
  mkdir -p "$STAGE"
  if [ ! -s "$KEY" ]; then
    if command -v create-munge-key >/dev/null 2>&1; then create-munge-key -f >/dev/null 2>&1 || true; fi
    [ -s "$KEY" ] || dd if=/dev/urandom of="$KEY" bs=1 count=1024 status=none
  fi
  chown munge:munge "$KEY"; chmod 400 "$KEY"
  # A lab-only convenience copy so the compute nodes can fetch the same key. In a real cluster the key
  # is never left world-readable on shared storage; remove it when the chapter is done (SLURM_CLEAN=1, see the header)
  install -m 0644 -o root -g root "$KEY" "$STAGE/munge.key"
  chmod 755 "$STAGE"
  log "munge key ready on login and staged for the compute nodes"
elif [ "$NO_KEY" = "1" ]; then
  log "munge installed; key NOT placed (--no-key): copy /etc/munge/munge.key from login yourself"
else
  for i in $(seq 1 12); do [ -s "$STAGE/munge.key" ] && break; sleep 5; done
  [ -s "$STAGE/munge.key" ] || die "$STAGE/munge.key not found. Run this on the login node first (and check /shared is mounted)."
  install -m 0400 -o munge -g munge "$STAGE/munge.key" "$KEY"
  log "munge key installed from the login node"
fi
[ -f "$KEY" ] && log "munge key fingerprint: $(sha256sum "$KEY" | cut -c1-12) (must be identical on every node)"

# ---- login node: template and checklist ---------------------------------------
if [ "$LAB_ROLE" = "login" ]; then
  cpus="$(nproc)"
  computes=(); lines=""
  IFS=',' read -ra pairs <<< "$LAB_NODES"
  for p in "${pairs[@]}"; do
    n="${p%%=*}"; ip="${p#*=}"
    case "$n" in compute*) computes+=("$n"); lines+="NodeName=$n NodeAddr=$ip CPUs=$cpus RealMemory=CHANGE_ME State=UNKNOWN"$'\n' ;; esac
  done
  nodelist="$(IFS=,; echo "${computes[*]}")"

  cat > "$STAGE/slurm.conf.template" <<EOF
# slurm.conf TEMPLATE for the lab. Copy to /etc/slurm/slurm.conf on EVERY node after you have
# replaced CHANGE_ME. Find RealMemory by running 'slurmd -C' on a compute node (it must not exceed
# what slurmd reports). The file must be identical on all nodes.
ClusterName=hpclab
SlurmctldHost=login
SlurmUser=slurm
SlurmctldPort=6817
SlurmdPort=6818
AuthType=auth/munge
MpiDefault=none
ProctrackType=proctrack/linuxproc
TaskPlugin=task/none
SwitchType=switch/none
ReturnToService=1
SchedulerType=sched/backfill
SelectType=select/cons_tres
SelectTypeParameters=CR_Core_Memory
StateSaveLocation=/var/spool/slurmctld
SlurmdSpoolDir=/var/spool/slurmd
SlurmctldPidFile=/var/run/slurm/slurmctld.pid
SlurmdPidFile=/var/run/slurm/slurmd.pid
SlurmctldLogFile=/var/log/slurm/slurmctld.log
SlurmdLogFile=/var/log/slurm/slurmd.log
AccountingStorageType=accounting_storage/none
JobAcctGatherType=jobacct_gather/none

# --- nodes (one line per compute node) ---
${lines}
# --- partition ---
PartitionName=debug Nodes=${nodelist} Default=YES MaxTime=INFINITE State=UP
EOF

  cat > "$STAGE/README.txt" <<EOF
CHECKLIST: build the Slurm cluster

Already done for you: the munge key is on every node (same key), the 'slurm' and 'munge'
accounts exist with the same IDs everywhere, repositories are ready, and a slurm.conf
template is next to this file. Munge and Slurm are NOT running yet.

 1. Start munge on every node and prove it works:
        sudo systemctl enable --now munge
        munge -n | unmunge            (should say STATUS: Success)
    Then prove it works ACROSS nodes (clocks must agree):
        munge -n | ssh <other-node> unmunge
 2. Find the Slurm packages (dnf search slurm). Install the controller side on login and the
    node side on the compute nodes. Note which packages each node needs.
 3. On a compute node run 'slurmd -C' and read the RealMemory value.
 4. Copy slurm.conf.template to /etc/slurm/slurm.conf, replace CHANGE_ME, and make the file
    identical on every node.
 5. Create the directories named in slurm.conf (spool, log, run) and give them to the 'slurm' user.
 6. Start slurmctld on login and slurmd on the compute nodes (enable them too).
 7. Check: sinfo   squeue   srun -N1 hostname

If something fails, read the logs (/var/log/slurm/ and 'journalctl -u slurmctld' / 'slurmd'),
and the three usual suspects: the clock, the munge key, and name resolution.

When you are done, run:  slurm-verify
When the chapter is done, remove the staged key (run on the host, not in the VM):
  SLURM_CLEAN=1 vagrant provision login --provision-with stage-clean,stage,stage-modules,slurm
EOF
  chmod 644 "$STAGE/slurm.conf.template" "$STAGE/README.txt"
  log "wrote $STAGE/slurm.conf.template and $STAGE/README.txt"
fi

# ---- pre-flight report -------------------------------------------------------
sync_state="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
[ "$sync_state" = "yes" ] && log "clock: synchronized" || warn "clock is not synchronized (munge fails when clocks differ). Run: lab-verify --fix"
IFS=',' read -ra pairs <<< "$LAB_NODES"
for p in "${pairs[@]}"; do
  n="${p%%=*}"; ip="${p#*=}"
  [ "$(getent hosts "$n" | awk '{print $1; exit}')" = "$ip" ] || warn "$n does not resolve to $ip (check /etc/hosts)"
done
if systemctl is-active --quiet munge 2>/dev/null; then log "note: munge is already running"; fi
log "Slurm prep complete on $LAB_NODE. Next: read $STAGE/README.txt"
