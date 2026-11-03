#!/usr/bin/env bash
# collect-evidence - gather the standard facts for a support ticket into one text file.
#
#   collect-evidence [USER] [JOBID] [options]
#
#   collect-evidence alice                 evidence about user alice on this node
#   collect-evidence alice 1234            ... plus Slurm details for job 1234
#   collect-evidence 1234                  job 1234 and the current user
#   collect-evidence                       the current user
#
# Options:
#   --jira          format for pasting into Jira (h3. headings and {code} blocks)
#   --job-output    also include the last 30 lines of the job's stdout/stderr files
#   --du            also measure the size of the user's home directory (can be slow)
#   --out FILE      write to FILE (default: ./evidence-<host>-<target>-<date>.txt; "-" = screen)
#   -h, --help      this help
#
# Read-only: it changes nothing. It collects system and account metadata, not file contents
# (unless --job-output), keys or passwords. Review the file before you attach it to a ticket.
# Run it in the same shell/session as the problem to capture that shell's modules and environment.
set -u

USER_T=""; JOB_T=""; OUT=""; JIRA=0; JOBOUT=0; DU=0
POS=()
usage() { awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; }
JOBRE='^[0-9]+([_.][0-9A-Za-z]+)?$'

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --jira) JIRA=1 ;;
    --job-output) JOBOUT=1 ;;
    --du) DU=1 ;;
    --out) shift; OUT="${1:-}"; [ -n "$OUT" ] || { echo "collect-evidence: --out needs a value" >&2; exit 2; } ;;
    -*) echo "collect-evidence: unknown option '$1' (see --help)" >&2; exit 2 ;;
    *) POS+=("$1") ;;
  esac
  shift
done
case "${#POS[@]}" in
  0) ;;
  1) if printf '%s' "${POS[0]}" | grep -Eq "$JOBRE"; then JOB_T="${POS[0]}"; else USER_T="${POS[0]}"; fi ;;
  2) USER_T="${POS[0]}"; JOB_T="${POS[1]}" ;;
  *) echo "collect-evidence: too many arguments (see --help)" >&2; exit 2 ;;
esac
[ -n "$USER_T" ] || USER_T="$(id -un)"
printf '%s' "$USER_T" | grep -Eq '^[A-Za-z_][A-Za-z0-9_.@-]*$' || { echo "collect-evidence: '$USER_T' is not a valid user name" >&2; exit 2; }
if [ -n "$JOB_T" ]; then
  printf '%s' "$JOB_T" | grep -Eq "$JOBRE" || { echo "collect-evidence: '$JOB_T' is not a valid job id" >&2; exit 2; }
fi

HOST="$(hostname -s 2>/dev/null || hostname)"
STAMP="$(date +%Y%m%d-%H%M)"
TARGET="$USER_T${JOB_T:+-job$JOB_T}"
[ -n "$OUT" ] || OUT="./evidence-$HOST-$TARGET-$STAMP.txt"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
exec 3>"$TMP"

SKIPPED=()
have()  { command -v "$1" >/dev/null 2>&1; }
emit()  { printf '%s\n' "$*" >&3; }
skip()  { SKIPPED+=("$1"); emit "(skipped: $1)"; }
section() { if [ "$JIRA" -eq 1 ]; then emit ""; emit "h3. $1"; else emit ""; emit "=== $1 ==="; fi; }

# show <timeout-seconds> <command...>: print the command and its output
show() {
  local t="$1"; shift
  if ! have "$1"; then skip "$1 is not installed"; return; fi
  [ "$JIRA" -eq 1 ] && emit "{code}"
  emit "\$ $*"
  timeout "$t" "$@" >&3 2>&1 || { rc=$?; [ "$rc" -eq 124 ] && emit "(timed out after ${t}s)"; }
  [ "$JIRA" -eq 1 ] && emit "{code}"
  return 0
}
# show_sh <timeout> <shell pipeline>: same, for pipelines
show_sh() {
  local t="$1" s="$2"
  [ "$JIRA" -eq 1 ] && emit "{code}"
  emit "\$ $s"
  timeout "$t" bash -c "$s" >&3 2>&1 || { rc=$?; [ "$rc" -eq 124 ] && emit "(timed out after ${t}s)"; }
  [ "$JIRA" -eq 1 ] && emit "{code}"
  return 0
}
# privileged: root, else sudo without a password, else skipped
PRIV=""
if [ "$(id -u)" -eq 0 ]; then PRIV=""; elif have sudo && sudo -n true 2>/dev/null; then PRIV="sudo -n"; else PRIV="NONE"; fi
show_priv() { # show_priv <timeout> <command...>
  local t="$1"; shift
  if [ "$PRIV" = NONE ]; then skip "$* needs root"; else show "$t" $PRIV "$@"; fi
}

USER_EXISTS=0; id "$USER_T" >/dev/null 2>&1 && USER_EXISTS=1
HOME_T=""; [ "$USER_EXISTS" -eq 1 ] && HOME_T="$(getent passwd "$USER_T" | cut -d: -f6)"

# ---- summary -------------------------------------------------------------------
section "Summary"
emit "Collected at : $(date '+%F %T %Z')"
emit "Collected by : $(id -un)"
emit "Host         : $(hostname -f 2>/dev/null || hostname)"
emit "OS           : $( . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
emit "Kernel       : $(uname -r)"
emit "Uptime/load  : $(uptime -p 2>/dev/null) | load $(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null)"
emit "Target user  : $USER_T$([ "$USER_EXISTS" -eq 0 ] && echo ' (NOT FOUND on this node)')"
[ -n "$JOB_T" ] && emit "Job          : $JOB_T"
emit "Note         : metadata only; review before attaching to a ticket."

# ---- account -------------------------------------------------------------------
section "Account: $USER_T"
if [ "$USER_EXISTS" -eq 1 ]; then
  show 10 id "$USER_T"
  show 10 getent passwd "$USER_T"
  [ -d "$HOME_T" ] && show 10 ls -ld "$HOME_T" || emit "(home directory $HOME_T does not exist or is not visible here)"
  [ -d "$HOME_T/.ssh" ] && show 10 ls -ld "$HOME_T/.ssh"
  show_priv 10 chage -l "$USER_T"
  show_priv 10 passwd -S "$USER_T"
  show 15 last -n 5 "$USER_T"
else
  emit "User '$USER_T' does not exist on this node (check: getent passwd $USER_T, and the identity service)."
fi

# ---- storage -------------------------------------------------------------------
section "Storage and quota"
show 20 df -hT -x tmpfs -x devtmpfs -x squashfs
show 20 df -iT -x tmpfs -x devtmpfs -x squashfs
show 15 findmnt -t nfs,nfs4,lustre
if [ -n "$HOME_T" ] && [ -d "$HOME_T" ]; then
  show 15 findmnt -T "$HOME_T"
  show 30 quota -s -u "$USER_T"
  if have lfs; then show 30 lfs quota -h -u "$USER_T" "$(findmnt -n -o TARGET -T "$HOME_T" 2>/dev/null || echo "$HOME_T")"; fi
  [ "$DU" -eq 1 ] && show 120 du -sh "$HOME_T"
fi

# ---- node load -----------------------------------------------------------------
section "Node health"
show 10 uptime
show 10 free -h
show_sh 10 "ps -eo pid,user,stat,etime,pcpu,pmem,comm --sort=-pcpu | head -n 8"
[ "$USER_EXISTS" -eq 1 ] && show_sh 10 "ps -u '$USER_T' -o pid,ppid,stat,etime,pcpu,pmem,args --sort=-pcpu | head -n 15"
show_sh 10 "systemctl --failed --no-pager --no-legend 2>&1 | head -n 15"
show_sh 10 "timedatectl show -p Timezone -p NTPSynchronized 2>&1"

# ---- environment of this shell (whitelist only; no secrets) --------------------
section "Environment of the shell running this tool"
for v in LOADEDMODULES CONDA_DEFAULT_ENV VIRTUAL_ENV SLURM_JOB_ID SLURM_JOB_NODELIST APPTAINER_NAME SINGULARITY_NAME; do
  [ -n "${!v:-}" ] && emit "$v=${!v}"
done
emit "PATH entries:"
printf '%s\n' "$PATH" | tr ':' '\n' | sed 's/^/  /' >&3
have python3 && emit "python3: $(command -v python3) ($(python3 --version 2>&1))"
show_sh 5 "ulimit -a"

# ---- slurm ---------------------------------------------------------------------
if have squeue || have sinfo; then
  section "Slurm"
  show 20 sinfo -N -o '%N %P %t %E'
  show 20 squeue -u "$USER_T" -o '%i %P %j %T %M %l %D %C %r'
  if [ -n "$JOB_T" ]; then
    show 20 squeue -j "$JOB_T" -o '%i %T %r %R'
    show 20 scontrol show job "$JOB_T"
    show 30 sacct -j "$JOB_T" -P --format=JobID,JobName%20,Partition,AllocCPUS,ReqMem,MaxRSS,Elapsed,Timelimit,State,ExitCode,NodeList%30
    nodes="$(scontrol show job "$JOB_T" 2>/dev/null | grep -o ' NodeList=[^ ]*' | head -1 | cut -d= -f2)"
    if [ -n "$nodes" ] && [ "$nodes" != "(null)" ]; then
      for n in $(scontrol show hostnames "$nodes" 2>/dev/null | head -n 8); do
        show_sh 15 "scontrol show node '$n' | grep -E 'NodeName|State=|Reason|CPUAlloc|RealMemory|AllocMem|Gres'"
      done
    fi
    if [ "$JOBOUT" -eq 1 ]; then
      for key in StdOut StdErr; do
        f="$(scontrol show job "$JOB_T" 2>/dev/null | grep -o " $key=[^ ]*" | head -1 | cut -d= -f2)"
        if [ -n "$f" ] && [ -r "$f" ]; then emit ""; emit "Last 30 lines of $key ($f):"; [ "$JIRA" -eq 1 ] && emit "{code}"; tail -n 30 "$f" >&3 2>&1; [ "$JIRA" -eq 1 ] && emit "{code}"
        else emit "($key file not found or not readable: ${f:-unknown})"; fi
      done
    fi
  fi
  since="$(date -d '1 day ago' +%F 2>/dev/null)"
  [ -n "$since" ] && show_sh 30 "sacct -u '$USER_T' -S $since -P --format=JobID,JobName%20,State,ExitCode,Elapsed,NodeList%24 2>&1 | tail -n 15"
fi

# ---- logs ----------------------------------------------------------------------
section "Recent warnings in the logs"
show_sh 20 "journalctl -p warning --since '1 hour ago' --no-pager -n 30 2>&1"
show_sh 20 "dmesg -T 2>&1 | tail -n 15"
if [ "$USER_EXISTS" -eq 1 ] && [ "$PRIV" != NONE ]; then
  show_sh 20 "$PRIV journalctl -u sshd --since '1 hour ago' --no-pager 2>&1 | grep -i -- '$USER_T' | tail -n 10"
fi

# ---- footer --------------------------------------------------------------------
section "Not collected"
if [ "${#SKIPPED[@]}" -eq 0 ]; then emit "Nothing was skipped."
else printf '%s\n' "${SKIPPED[@]}" | sort -u | sed 's/^/- /' >&3; fi

exec 3>&-
if [ "$OUT" = "-" ]; then cat "$TMP"
else
  mv "$TMP" "$OUT" && trap - EXIT
  chmod 600 "$OUT" 2>/dev/null
  echo "Evidence written to: $OUT"
  echo "Review it, then attach or paste it into the ticket."
fi
