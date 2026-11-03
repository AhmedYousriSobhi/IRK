#!/usr/bin/env bash
# node-health - one-screen health summary of a node: Slurm view plus operating-system view.
#
#   node-health              this node
#   node-health compute1     another node (the Slurm view always; the OS view over SSH if you can log in)
#   node-health --os-only    only the operating-system view of this node (used for the SSH case)
#
# Read-only. Each line is tagged [ OK ], [WARN], [FAIL] or [INFO]; the last line is the verdict.
# Exit code: 0 = no failures (warnings allowed), 1 = at least one failure.
set -u

usage() { awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; }
OS_ONLY=0; TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --os-only) OS_ONLY=1 ;;
    -*) echo "node-health: unknown option '$1' (see --help)" >&2; exit 2 ;;
    *)  TARGET="$1" ;;
  esac
  shift
done
LOCAL="$(hostname -s 2>/dev/null || hostname)"
[ -n "$TARGET" ] || TARGET="$LOCAL"
printf '%s' "$TARGET" | grep -Eq '^[A-Za-z0-9][A-Za-z0-9._-]*$' || { echo "node-health: '$TARGET' is not a valid node name" >&2; exit 2; }

nok=0; nwarn=0; nfail=0
line() {  # line <tag> <label> <text>
  case "$1" in OK) nok=$((nok+1)); t="[ OK ]" ;; WARN) nwarn=$((nwarn+1)); t="[WARN]" ;; FAIL) nfail=$((nfail+1)); t="[FAIL]" ;; *) t="[INFO]" ;; esac
  printf '%s %-12s %s\n' "$t" "$2" "$3"
}
have() { command -v "$1" >/dev/null 2>&1; }

# ---- Slurm view ------------------------------------------------------------------------
slurm_view() {
  have scontrol || { line INFO "Slurm" "scontrol not found on this node (no Slurm view)"; return; }
  local rec; rec="$(timeout 15 scontrol -o show node "$TARGET" 2>&1)"
  if [ -z "$rec" ] || echo "$rec" | grep -qi 'not found\|invalid\|error'; then
    line INFO "Slurm" "$TARGET is not known to Slurm ($(echo "$rec" | head -1 | cut -c1-60))"; return
  fi
  kv() { echo "$rec" | tr ' ' '\n' | grep -m1 "^$1=" | cut -d= -f2-; }
  local state reason cputot cpualloc cpuload real alloc free gres
  state="$(kv State)"; cputot="$(kv CPUTot)"; cpualloc="$(kv CPUAlloc)"; cpuload="$(kv CPULoad)"
  real="$(kv RealMemory)"; alloc="$(kv AllocMem)"; free="$(kv FreeMem)"; gres="$(kv Gres)"
  reason="$(echo "$rec" | sed -n 's/.*Reason=\(.*\) \[.*\]$/\1/p; s/.*Reason=\([^ ]*\).*/\1/p' | head -1)"
  case "$state" in
    *DOWN*|*INVAL*|*FAIL*|*NOT_RESPONDING*|*UNK*) line FAIL "Slurm state" "$state${reason:+ (reason: $reason)}" ;;
    *DRAIN*) line WARN "Slurm state" "$state${reason:+ (reason: $reason)}" ;;
    *) line OK "Slurm state" "$state" ;;
  esac
  line INFO "Slurm CPUs" "${cpualloc:-?} of ${cputot:-?} allocated, load ${cpuload:-?}"
  line INFO "Slurm memory" "${alloc:-?} MB allocated of ${real:-?} MB configured, ${free:-?} MB free"
  [ -n "$gres" ] && [ "$gres" != "(null)" ] && line INFO "Slurm GRES" "$gres"
}

# ---- operating-system view -------------------------------------------------------------
os_view() {
  local cpus load1 ratio
  cpus="$(nproc 2>/dev/null || echo 1)"; load1="$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo 0)"
  ratio="$(awk -v l="$load1" -v c="$cpus" 'BEGIN {printf "%.2f", l / c}')"
  if awk -v r="$ratio" 'BEGIN {exit !(r > 2)}'; then line FAIL "Load" "$load1 on $cpus CPU(s) (${ratio} per CPU): the node is overloaded"
  elif awk -v r="$ratio" 'BEGIN {exit !(r > 1)}'; then line WARN "Load" "$load1 on $cpus CPU(s) (${ratio} per CPU)"
  else line OK "Load" "$load1 on $cpus CPU(s)"; fi
  if awk -v r="$ratio" 'BEGIN {exit !(r > 1)}'; then
    top1="$(ps -eo pcpu,user,comm --sort=-pcpu 2>/dev/null | sed -n '2p' | awk '{print $3" ("$2", "$1"% CPU)"}')"
    [ -n "$top1" ] && line INFO "Top process" "$top1"
  fi

  local mt ma sw st pct
  mt="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"; ma="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
  if [ -n "$mt" ] && [ -n "$ma" ] && [ "$mt" -gt 0 ]; then
    pct=$(( ma * 100 / mt ))
    txt="$(( ma / 1024 )) MB available of $(( mt / 1024 )) MB (${pct}%)"
    if [ "$pct" -lt 5 ]; then line FAIL "Memory" "$txt"; elif [ "$pct" -lt 10 ]; then line WARN "Memory" "$txt"; else line OK "Memory" "$txt"; fi
  fi
  sw="$(awk '/^SwapTotal:/ {print $2}' /proc/meminfo)"; st="$(awk '/^SwapFree:/ {print $2}' /proc/meminfo)"
  if [ -n "$sw" ] && [ "$sw" -gt 0 ]; then
    pct=$(( (sw - st) * 100 / sw ))
    if [ "$pct" -gt 50 ]; then line WARN "Swap" "${pct}% of swap in use: the node is short of memory"; else line OK "Swap" "${pct}% in use"; fi
  else line INFO "Swap" "none configured"; fi

  # filesystems: space and inodes (local ones only: df on a hung network mount would block this tool)
  local fs use mp
  while read -r fs use mp; do
    [ -n "$mp" ] || continue; use="${use%\%}"
    if [ "$use" -ge 98 ]; then line FAIL "Disk $mp" "${use}% full"; elif [ "$use" -ge 90 ]; then line WARN "Disk $mp" "${use}% full"; fi
  done < <(df -P -l -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {print $1, $5, $6}')
  while read -r fs use mp; do
    [ -n "$mp" ] || continue; use="${use%\%}"; [ "$use" = "-" ] && continue
    if [ "$use" -ge 98 ]; then line FAIL "Inodes $mp" "${use}% used"; elif [ "$use" -ge 90 ]; then line WARN "Inodes $mp" "${use}% used"; fi
  done < <(df -Pi -l -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1 {print $1, $5, $6}')
  line INFO "Disk root" "$(df -Ph / 2>/dev/null | awk 'NR==2 {print $5" used, "$4" free"}')"

  # network filesystems must answer
  while read -r mp; do
    [ -n "$mp" ] || continue
    # df asks the server (stat on the mount point can be answered from the cache), so it is the real test
    if dfout="$(timeout 5 df -P "$mp" 2>/dev/null)"; then
      use="$(echo "$dfout" | awk 'NR==2 {gsub("%","",$5); print $5}')"
      if [ -n "$use" ] && [ "$use" -ge 98 ]; then line FAIL "Mount $mp" "responds, but ${use}% full"
      elif [ -n "$use" ] && [ "$use" -ge 90 ]; then line WARN "Mount $mp" "responds, ${use}% full"
      else line OK "Mount $mp" "responds"; fi
    else line FAIL "Mount $mp" "does not answer within 5 s (hung or stale)"; fi
  done < <(findmnt -rn -t nfs,nfs4,lustre -o TARGET 2>/dev/null)

  # services that exist on this node
  local svc active enabled
  for svc in sshd chronyd munge slurmd slurmctld crond nfs-server; do
    systemctl list-unit-files "$svc.service" --no-legend 2>/dev/null | grep -q . || continue
    if systemctl is-active --quiet "$svc" 2>/dev/null; then line OK "Service" "$svc running"
    elif systemctl is-enabled --quiet "$svc" 2>/dev/null; then line FAIL "Service" "$svc is enabled but not running"
    else line INFO "Service" "$svc installed but disabled"; fi
  done
  if have timedatectl; then
    if [ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" = "yes" ]; then line OK "Clock" "synchronized"
    else line WARN "Clock" "not synchronized (munge and logs depend on correct time)"; fi
  fi
  local failed; failed="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | head -5 | tr '\n' ' ')"
  [ -n "$failed" ] && line WARN "Failed units" "$failed"

  if have nvidia-smi; then
    local gpu; gpu="$(timeout 15 nvidia-smi --query-gpu=index,name,temperature.gpu,utilization.gpu,memory.used,memory.total --format=csv,noheader 2>&1)"
    if [ $? -ne 0 ]; then line FAIL "GPU" "nvidia-smi failed: $(echo "$gpu" | head -1 | cut -c1-70)"
    else echo "$gpu" | while IFS= read -r g; do line INFO "GPU" "$g"; done; fi
  fi
}

# ---- run -------------------------------------------------------------------------------
if [ "$OS_ONLY" -eq 1 ]; then os_view
else
  echo "Node health: $TARGET   ($(date '+%F %T'))"; echo
  slurm_view
  if [ "$TARGET" = "$LOCAL" ] || [ "$TARGET" = "$(hostname -f 2>/dev/null)" ]; then os_view
  else
    out="$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new "$TARGET" node-health --os-only 2>/dev/null)"
    if [ -n "$out" ]; then
      echo "$out"
      nok=$((nok + $(echo "$out" | grep -c '^\[ OK \]'))); nwarn=$((nwarn + $(echo "$out" | grep -c '^\[WARN\]'))); nfail=$((nfail + $(echo "$out" | grep -c '^\[FAIL\]')))
    else line INFO "OS view" "cannot log in to $TARGET without a password (set up SSH keys) or node-health is missing there; run node-health on $TARGET itself"; fi
  fi
  echo
  if [ "$nfail" -gt 0 ]; then echo "Verdict: PROBLEM ($nfail failed, $nwarn warnings)"; exit 1
  elif [ "$nwarn" -gt 0 ]; then echo "Verdict: ATTENTION ($nwarn warnings)"; exit 0
  else echo "Verdict: HEALTHY"; exit 0; fi
fi
[ "$nfail" -eq 0 ]
