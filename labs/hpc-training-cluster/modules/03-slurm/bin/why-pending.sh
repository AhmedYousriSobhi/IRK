#!/usr/bin/env bash
# why-pending - explain in plain words why a Slurm job is waiting, and what to check first.
#
#   why-pending 1234            explain job 1234
#   why-pending                 explain every pending job of the current user
#   why-pending -u alice        explain every pending job of user alice
#   why-pending --reason Priority   explain a reason code (no cluster needed)
#   why-pending --codes         list the reason codes this tool knows (a glossary)
#
# Read-only. For each job it shows the reason code, what it means for the user, who has to act
# (wait, the job's owner, or an administrator), the first command to run, the job's request,
# the expected start time and the state of the partition. Use it to understand the user's
# question before you answer; use collect-evidence when you need to escalate.
set -u

usage() { awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; }
JOBRE='^[0-9]+(_[0-9]+)?$'
ID=""; USERQ=""; REASON_ARG=""; CODES=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -u|--user) shift; USERQ="${1:-}"; [ -n "$USERQ" ] || { echo "why-pending: -u needs a user name" >&2; exit 2; } ;;
    --reason)  shift; REASON_ARG="${1:-}"; [ -n "$REASON_ARG" ] || { echo "why-pending: --reason needs a code" >&2; exit 2; } ;;
    --codes)   CODES=1 ;;
    -*) echo "why-pending: unknown option '$1' (see --help)" >&2; exit 2 ;;
    *)  if printf '%s' "$1" | grep -Eq "$JOBRE" && [ -z "$ID" ]; then ID="$1"
        else echo "why-pending: '$1' is not a job id" >&2; exit 2; fi ;;
  esac
  shift
done
if [ -n "$USERQ" ]; then
  printf '%s' "$USERQ" | grep -Eq '^[A-Za-z_][A-Za-z0-9_.@-]*$' || { echo "why-pending: '$USERQ' is not a valid user name" >&2; exit 2; }
fi

# ---- the knowledge: reason code -> plain words ------------------------------------
# Sets PLAIN, CHECK, WHO (wait|user|admin|wait-or-admin|unknown) and NEVER (1 = will not start by itself).
explain() {
  PLAIN=""; CHECK=""; WHO="unknown"; NEVER=0
  case "$1" in
    None)
      PLAIN="No reason has been recorded yet. This is normal for a job submitted a moment ago: the scheduler has not looked at it yet."
      CHECK="Run squeue again in a minute."; WHO=wait ;;
    Priority)
      PLAIN="Other jobs in the same partition have a higher priority and are ahead of this one. Nothing is wrong with the job."
      CHECK="sprio -j @ID@   (priority factors)    squeue -p @PART@ --sort=-p   (queue order)"; WHO=wait ;;
    Resources)
      PLAIN="The job is at the front of the queue, but the CPUs, memory or GPUs it asked for are not free yet. It starts when running jobs finish."
      CHECK="sinfo -p @PART@ -o '%P %t %D %C %m %G'   (what is free) and compare with the request. A smaller request often starts sooner."; WHO=wait ;;
    Dependency)
      PLAIN="The job waits for another job it depends on (--dependency) to finish first."
      CHECK="scontrol show job @ID@ | grep -i dependency    then    squeue -j <the other job id>"; WHO=wait ;;
    DependencyNeverSatisfied)
      PLAIN="The job it depends on ended in a way that can never satisfy the dependency (for example it failed), so this job will never start."
      CHECK="scontrol show job @ID@ | grep -i dependency    then    sacct -j <the other job id>. The owner cancels (scancel @ID@) and resubmits."; WHO=user; NEVER=1 ;;
    JobHeldUser)
      PLAIN="The job was put on hold by its owner (--hold or scontrol hold) and will not start until it is released."
      CHECK="The owner releases it:  scontrol release @ID@"; WHO=user ;;
    JobHeldAdmin)
      PLAIN="An administrator put this job on hold."
      CHECK="Ask the administrators why. Only they can release it (scontrol release @ID@)."; WHO=admin ;;
    BeginTime)
      PLAIN="The job was submitted with a start time in the future (--begin), so it is deliberately waiting."
      CHECK="scontrol show job @ID@ | grep -i StartTime"; WHO=wait ;;
    ReqNodeNotAvail*|NodeDown)
      PLAIN="A node the job needs is not available: it is down, drained, or reserved (for example for maintenance). It can also mean every node of the partition is unavailable."
      CHECK="sinfo -R   (nodes and why they are unavailable)    scontrol show reservation"; WHO=admin ;;
    PartitionDown)
      PLAIN="The partition is down, so no job in it can start."
      CHECK="sinfo -p @PART@"; WHO=admin ;;
    PartitionInactive)
      PLAIN="The partition is not accepting jobs to run right now."
      CHECK="scontrol show partition @PART@ | grep -i State"; WHO=admin ;;
    PartitionTimeLimit)
      PLAIN="The job asks for more run time than the partition allows, so it will never start as submitted."
      CHECK="scontrol show partition @PART@ | grep -i MaxTime   and compare with the job's time limit. Fix: scontrol update JobId=@ID@ TimeLimit=<shorter>, or resubmit."; WHO=user; NEVER=1 ;;
    PartitionNodeLimit)
      PLAIN="The job asks for more nodes than the partition allows, so it will never start as submitted."
      CHECK="scontrol show partition @PART@ | grep -i MaxNodes   and compare with the job's node count. Resubmit with fewer nodes."; WHO=user; NEVER=1 ;;
    QOS*)
      PLAIN="A usage limit (QOS) has been reached, for example the maximum number of running jobs or CPUs per user. The job starts when earlier jobs finish."
      CHECK="sacctmgr show qos format=Name,MaxJobsPU,MaxTRESPU    squeue -u @USER@"; WHO=wait ;;
    Assoc*)
      PLAIN="The user's account (or group) has reached a cap on jobs or resources. The job starts when earlier jobs finish or the limit is changed."
      CHECK="sacctmgr show assoc user=@USER@ format=Account,Partition,GrpTRES,MaxJobs"; WHO=wait-or-admin ;;
    InvalidAccount|InvalidQOS)
      PLAIN="The account or QOS named in the job is not valid for this user, so the job will never start."
      CHECK="sacctmgr show assoc user=@USER@ format=Account,QOS. The owner cancels (scancel @ID@) and resubmits with a valid --account/--qos."; WHO=user; NEVER=1 ;;
    Reservation)
      PLAIN="The job is tied to a reservation that is not active or not available yet."
      CHECK="scontrol show reservation"; WHO=wait ;;
    Licenses)
      PLAIN="The job is waiting for a software license that is currently in use."
      CHECK="scontrol show licenses"; WHO=wait ;;
    BadConstraints)
      PLAIN="The job's constraints (features, specific nodes, GPUs) cannot be met by the cluster, so it will never start."
      CHECK="scontrol show job @ID@ | grep -iE 'Features|Gres|TRES'    sinfo -o '%N %f %G'"; WHO=user; NEVER=1 ;;
    JobArrayTaskLimit)
      PLAIN="This array job reached its throttle (the %N in --array=...%N). More tasks start as running ones finish."
      CHECK="scontrol show job @ID@ | grep -i ArrayTaskThrottle"; WHO=wait ;;
    launch_failed_requeued_held)
      PLAIN="The job failed to launch on a node and was held automatically."
      CHECK="scontrol show job @ID@ | grep -iE 'Reason|NodeList'   and the slurmd log on that node."; WHO=admin; NEVER=1 ;;
    *)
      PLAIN="This reason code is not in the built-in list."
      CHECK="man squeue   (section JOB REASON CODES)    scontrol show job @ID@"; WHO=unknown ;;
  esac
}
KNOWN_CODES="None Priority Resources Dependency DependencyNeverSatisfied JobHeldUser JobHeldAdmin BeginTime ReqNodeNotAvail NodeDown PartitionDown PartitionInactive PartitionTimeLimit PartitionNodeLimit QOSMaxJobsPerUserLimit AssocGrpCpuLimit InvalidAccount InvalidQOS Reservation Licenses BadConstraints JobArrayTaskLimit launch_failed_requeued_held"

who_text() {
  case "$1" in
    wait) echo "Nobody. The job just has to wait." ;;
    user) echo "The job's owner (the user)." ;;
    admin) echo "An administrator." ;;
    wait-or-admin) echo "Wait, or an administrator if the limit should change." ;;
    *) echo "Not sure. Check the first command below." ;;
  esac
}
fill() { local t="$1"; t="${t//@ID@/$2}"; t="${t//@PART@/$3}"; t="${t//@USER@/$4}"; printf '%s' "$t"; }

# ---- modes that need no cluster -----------------------------------------------------
if [ "$CODES" -eq 1 ]; then
  echo "Reason codes known to why-pending (the first word is what squeue shows):"; echo
  for c in $KNOWN_CODES; do explain "$c"; printf '%-28s %s\n' "$c" "$PLAIN"; done
  exit 0
fi
if [ -n "$REASON_ARG" ]; then
  explain "$REASON_ARG"
  echo "Reason     : $REASON_ARG"
  echo "Meaning    : $PLAIN"
  echo "Who acts   : $(who_text "$WHO")"
  [ "$NEVER" -eq 1 ] && echo "Note       : the job will not start by itself."
  echo "First check: $(fill "$CHECK" "<jobid>" "<partition>" "<user>")"
  exit 0
fi

if ! command -v squeue >/dev/null 2>&1; then
  echo "why-pending: Slurm commands not found on this node. Use --reason <code> to explain a code." >&2; exit 2
fi

# ---- explain one job -------------------------------------------------------------------
LINES=0
explain_job() {  # reads one squeue line: id|user|state|reason|partition|nodes|cpus|mem|limit|prio|start|gres|nodelist
  local jid user state reason part nodes cpus mem limit prio start gres nodelist
  IFS='|' read -r jid user state reason part nodes cpus mem limit prio start gres nodelist <<< "$1"
  LINES=$((LINES + 1))
  echo "------------------------------------------------------------"
  echo "Job $jid   user $user   partition $part"
  if [ "$state" != "PENDING" ]; then
    echo "State      : $state (not pending)"
    case "$state" in RUNNING) echo "Running on : ${nodelist:-unknown}" ;; esac
    return
  fi
  explain "$reason"
  echo "State      : PENDING"
  echo "Reason     : $reason"
  echo "Meaning    : $PLAIN"
  echo "Who acts   : $(who_text "$WHO")"
  [ "$NEVER" -eq 1 ] && echo "Warning    : this job will not start by itself."
  echo "First check: $(fill "$CHECK" "$jid" "$part" "$user")"
  case "$gres" in ""|N/A|"(null)") gres="" ;; esac
  echo "Request    : $nodes node(s), $cpus CPU(s), memory $mem, time limit $limit${gres:+, gres $gres}"
  case "$start" in ""|N/A|"Unknown") echo "Expected start: not estimated yet" ;; *) echo "Expected start: $start" ;; esac
  echo "Priority   : $prio"
  if command -v sinfo >/dev/null 2>&1; then
    local pstate; pstate="$(sinfo -h -p "$part" -o '%D %t' 2>/dev/null | awk '{c[$2]+=$1} END {for (s in c) printf "%d %s, ", c[s], s}' | sed 's/, $//')"
    [ -n "$pstate" ] && echo "Partition now: $pstate"
  fi
}

FORMAT='%i|%u|%T|%r|%P|%D|%C|%m|%l|%Q|%S|%b|%N'
if [ -n "$ID" ]; then
  out="$(squeue -h -j "$ID" -o "$FORMAT" 2>&1)"; rc=$?
  if [ $rc -ne 0 ] || [ -z "$out" ]; then
    # not in the queue any more: ask accounting if it is available
    if command -v sacct >/dev/null 2>&1 && acc="$(sacct -n -P -X -j "$ID" -o State,ExitCode,Elapsed,End 2>/dev/null | head -1)" && [ -n "$acc" ]; then
      IFS='|' read -r st ex el en <<< "$acc"
      echo "Job $ID is not pending and not in the queue. Accounting says: state $st, exit code $ex, ran $el, ended $en."
      echo "If the user's question is why it failed, collect the facts with:  collect-evidence <user> $ID"
    else
      echo "Job $ID was not found. Check the job id (squeue -u <user>); a finished job needs Slurm accounting to be looked up."
      [ $rc -ne 0 ] && echo "squeue said: $(echo "$out" | head -1)"
    fi
    exit 1
  fi
  while IFS= read -r line; do [ -n "$line" ] && explain_job "$line"; done <<< "$out"
else
  who="${USERQ:-$(id -un)}"
  out="$(squeue -h -u "$who" -t PENDING -o "$FORMAT" 2>&1)"
  if [ -z "$out" ]; then echo "$who has no pending jobs."; exit 0; fi
  if echo "$out" | head -1 | grep -qiE 'error|invalid'; then echo "squeue said: $(echo "$out" | head -1)" >&2; exit 1; fi
  while IFS= read -r line; do [ -n "$line" ] && explain_job "$line"; done <<< "$out"
fi
echo "------------------------------------------------------------"
echo "Need to escalate? Gather the facts first:  collect-evidence <user> <jobid>"
