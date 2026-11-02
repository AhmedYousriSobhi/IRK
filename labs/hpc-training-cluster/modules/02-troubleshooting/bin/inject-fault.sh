#!/usr/bin/env bash
# inject-fault - plant a realistic problem on a lab node for troubleshooting practice.
#
#   sudo inject-fault <scenario>          plant a specific problem
#   sudo inject-fault random [--seed N]   plant a random one (the name is not shown;
#                                         the same seed gives the same problem, so an
#                                         admin can give each learner a seed)
#   sudo inject-fault --check             is the planted problem fixed? (exit 0 yes, 1 no, 2 none active)
#   sudo inject-fault --ticket            show the user's complaint again
#   sudo inject-fault --reveal            show what was planted and how to fix it
#   sudo inject-fault --revert            undo the problem and restore the node
#   inject-fault --list                   list scenarios (this reveals the possible causes)
#
# Options: --yes  skip the confirmation prompt
#
# Use it only on lab VMs. It refuses to run on a machine that is not a provisioned lab node.
# Disk, inode and process faults vanish at reboot, the others persist. One at a time.
set -uo pipefail

RELEASE_FILE="${LAB_RELEASE_FILE:-/etc/hpc-lab-release}"
STATE="${LAB_FAULT_DIR:-/var/lib/hpc-lab/fault}"
DATA="$STATE/data"
SCENARIOS="disk-full inode-exhaustion service-stopped service-failed bad-permissions ssh-keys runaway-process locked-user hosts-entry nfs-unmounted"

die()  { echo "inject-fault: $*" >&2; exit 1; }
need_root() { [ "$(id -u)" -eq 0 ] || die "this needs root. Run it with sudo."; }
fn()   { echo "${1//-/_}"; }

load_release() {
  [ -r "$RELEASE_FILE" ] || die "this is not a provisioned lab node ($RELEASE_FILE not found)."
  # shellcheck disable=SC1090
  . "$RELEASE_FILE"
  : "${LAB_NODE:?}" "${LAB_ROLE:?}" "${LAB_NODES:?}" "${LAB_SHARED:?}"
}

eligible() {  # can this scenario run on this node's role?
  case "$1" in
    bad-permissions|ssh-keys) [ "$LAB_ROLE" = login ] ;;
    nfs-unmounted)            [ "$LAB_ROLE" = compute ] ;;
    *)                        return 0 ;;
  esac
}

role_note() {
  case "$1" in
    bad-permissions|ssh-keys) echo "login node only" ;;
    nfs-unmounted)            echo "compute nodes only" ;;
    *)                        echo "any node" ;;
  esac
}

# ---- small helpers ----------------------------------------------------------
mode_has_none() {  # mode_has_none <path> <octal-mask>: true if none of the mask bits are set
  [ -e "$1" ] || return 0
  [ $(( 8#$(stat -c %a "$1") & 8#$2 )) -eq 0 ]
}

make_loop_fs() {  # make_loop_fs <name> <size-MB> <mountpoint> [mkfs.ext4 options...]
  local name="$1" size="$2" mp="$3"; shift 3
  local img="$DATA/$name.img"
  command -v mkfs.ext4 >/dev/null || { echo "mkfs.ext4 not found"; return 1; }
  mkdir -p "$mp"
  dd if=/dev/zero of="$img" bs=1M count="$size" status=none || return 1
  mkfs.ext4 -q -F "$@" "$img" || return 1
  mount -o loop "$img" "$mp" || return 1
  echo "$mp" >> "$DATA/mounts"
}

peer_node() {  # a node other than this one: a compute node from the login node, else login
  if [ "$LAB_ROLE" = login ]; then
    echo "$LAB_NODES" | tr ',' '\n' | grep -v "^$LAB_NODE=" | grep -m1 '^compute' | cut -d= -f1
  else
    echo login
  fi
}
node_ip() { echo "$LAB_NODES" | tr ',' '\n' | grep "^$1=" | cut -d= -f2; }

# ---- scenario: disk-full ----------------------------------------------------
ticket_disk_full()   { echo "The analysis application on this node cannot save its results: it reports 'No space left on device'. Nobody deleted anything. Please investigate (the application writes under /data/app)."; }
solution_disk_full() { echo "A large leftover file fills /data/app. Find it with 'df -h /data/app' and 'du -sh /data/app/*' (then into logs/), remove or truncate it, and confirm free space."; }
inject_disk_full() {
  make_loop_fs diskfull 64 /data/app -m 0 || return 1
  mkdir -p /data/app/logs
  echo "mode: batch" > /data/app/config.yml
  fallocate -l 12M /data/app/logs/app-2026.log
  dd if=/dev/zero of=/data/app/logs/core.dump.tmp bs=1M status=none 2>/dev/null || true
  chown -R carol:hpc-users /data/app 2>/dev/null || true
  sync
}
check_disk_full() { mountpoint -q /data/app && [ "$(df -Pk /data/app | awk 'NR==2{print $4}')" -gt 10240 ]; }
revert_disk_full() { :; }

# ---- scenario: inode-exhaustion ---------------------------------------------
ticket_inode_exhaustion()   { echo "Writing new files under /data/spool fails with 'No space left on device', but the user insists the disk is not full. Please investigate."; }
solution_inode_exhaustion() { echo "The filesystem ran out of inodes, not space. Confirm with 'df -h /data/spool' versus 'df -i /data/spool', find the directory with huge numbers of tiny files (/data/spool/queue), and remove them."; }
inject_inode_exhaustion() {
  make_loop_fs inodes 32 /data/spool -N 1024 -m 0 || return 1
  mkdir -p /data/spool/queue
  local i=0
  cd /data/spool/queue || return 1
  while { : > "job-$i.tmp"; } 2>/dev/null; do
    i=$((i + 1)); [ "$i" -gt 100000 ] && break
  done
  cd / || true
  chown -R carol:hpc-users /data/spool/queue 2>/dev/null || true
}
check_inode_exhaustion() { mountpoint -q /data/spool && [ "$(df -Pi /data/spool | awk 'NR==2{print $4}')" -gt 100 ]; }
revert_inode_exhaustion() { :; }

# ---- scenario: service-stopped (cron) ---------------------------------------
ticket_service_stopped()   { echo "Scheduled jobs (cron) on this node stopped running since this morning, and nobody changed the crontabs."; }
solution_service_stopped() { echo "The cron daemon was stopped and disabled. Check 'systemctl status crond', then 'systemctl enable --now crond' so it also survives a reboot."; }
inject_service_stopped() {
  systemctl cat crond >/dev/null 2>&1 || { echo "crond is not installed on this node"; return 1; }
  systemctl stop crond && systemctl disable crond >/dev/null 2>&1
}
check_service_stopped() { systemctl is-active --quiet crond && systemctl is-enabled --quiet crond; }
revert_service_stopped() { systemctl enable --now crond >/dev/null 2>&1; }

# ---- scenario: service-failed (chronyd, bad configuration) -------------------
ticket_service_failed()   { echo "This node's clock is drifting and time synchronization looks broken: 'chronyc' cannot talk to the daemon, and the service will not stay up."; }
solution_service_failed() { echo "chronyd fails on a configuration error. Read 'systemctl status chronyd' and 'journalctl -u chronyd' to find the bad line in /etc/chrony.conf, fix it, and restart the service."; }
inject_service_failed() {
  cp -a /etc/chrony.conf "$DATA/chrony.conf.orig" || return 1
  if grep -q '^driftfile' /etc/chrony.conf; then
    sed -i 's/^driftfile/driftfle/' /etc/chrony.conf
  else
    echo "driftfle /var/lib/chrony/drift" >> /etc/chrony.conf
  fi
  systemctl restart chronyd >/dev/null 2>&1 || true
}
check_service_failed() { systemctl is-active --quiet chronyd; }
revert_service_failed() { cp -a "$DATA/chrony.conf.orig" /etc/chrony.conf && systemctl restart chronyd >/dev/null 2>&1; }

# ---- scenario: bad-permissions (login node) ---------------------------------
ticket_bad_permissions()   { echo "alice and bob (project proj-a) suddenly get 'Permission denied' in $LAB_SHARED/project/proj-a. It worked yesterday."; }
solution_bad_permissions() { echo "Ownership and mode of $LAB_SHARED/project/proj-a were changed. Compare 'ls -ld' with what the project needs: group proj-a with rwx for the group (ideally mode 2770, group-owned by proj-a, with setgid)."; }
inject_bad_permissions() {
  local d="$LAB_SHARED/project/proj-a"
  [ -d "$d" ] || { echo "missing $d"; return 1; }
  stat -c '%a %U %G' "$d" > "$DATA/proj-a.stat"
  chown root:root "$d" && chmod 700 "$d"
}
check_bad_permissions() {
  local d="$LAB_SHARED/project/proj-a"
  [ "$(stat -c %G "$d")" = "proj-a" ] && [ $(( 8#$(stat -c %a "$d") & 8#070 )) -eq $((8#070)) ]
}
revert_bad_permissions() {
  local d="$LAB_SHARED/project/proj-a"
  chown root:proj-a "$d" && chmod 2770 "$d"
}

# ---- scenario: ssh-keys (login node, alice's passwordless login) ------------
ticket_ssh_keys()   { echo "alice's passwordless ssh from the login node to the compute nodes stopped working: it asks for a password now. She says she only ran a 'chmod -R 777' on her home directory."; }
solution_ssh_keys() { echo "Permissions on alice's home, ~/.ssh, authorized_keys and the private key are too open, so sshd (StrictModes) and ssh refuse them. Run 'ssh -v' as alice and check 'journalctl -u sshd' for 'bad ownership or modes'. Fix: home 700 (or 755), ~/.ssh 700, authorized_keys and id_ed25519 600."; }
inject_ssh_keys() {
  local h="$LAB_SHARED/home/alice" s="$LAB_SHARED/home/alice/.ssh"
  id alice >/dev/null 2>&1 && [ -d "$h" ] || { echo "user alice or her home is missing"; return 1; }
  runuser -u alice -- mkdir -p "$s"
  if [ ! -f "$s/id_ed25519" ]; then
    runuser -u alice -- ssh-keygen -q -t ed25519 -N '' -f "$s/id_ed25519" || return 1
    touch "$DATA/created-key"
  fi
  if ! grep -qF "$(cat "$s/id_ed25519.pub")" "$s/authorized_keys" 2>/dev/null; then
    cat "$s/id_ed25519.pub" >> "$s/authorized_keys"
    chown alice:hpc-users "$s/authorized_keys"
    touch "$DATA/added-authkey"
  fi
  chmod 777 "$h" "$s" && chmod 666 "$s/authorized_keys" "$s/id_ed25519"
}
check_ssh_keys() {
  local h="$LAB_SHARED/home/alice" s="$LAB_SHARED/home/alice/.ssh"
  mode_has_none "$h" 022 && mode_has_none "$s" 077 \
    && mode_has_none "$s/authorized_keys" 077 && mode_has_none "$s/id_ed25519" 077
}
revert_ssh_keys() {
  local h="$LAB_SHARED/home/alice" s="$LAB_SHARED/home/alice/.ssh"
  chmod 700 "$h" "$s"; chmod 600 "$s/authorized_keys" "$s/id_ed25519" 2>/dev/null
  if [ -f "$DATA/added-authkey" ] && [ -f "$s/id_ed25519.pub" ]; then
    grep -vF "$(cat "$s/id_ed25519.pub")" "$s/authorized_keys" > "$s/authorized_keys.new" 2>/dev/null
    cat "$s/authorized_keys.new" > "$s/authorized_keys"; rm -f "$s/authorized_keys.new"
    [ -s "$s/authorized_keys" ] || rm -f "$s/authorized_keys"
  fi
  [ -f "$DATA/created-key" ] && rm -f "$s/id_ed25519" "$s/id_ed25519.pub"
  return 0
}

# ---- scenario: runaway-process ----------------------------------------------
ticket_runaway_process()   { echo "This node has been extremely slow for the past hour: interactive commands lag and everything feels sluggish."; }
solution_runaway_process() { echo "Two CPU-hungry processes owned by carol ('postproc_job.sh') are running. Find them with 'top' or 'ps aux --sort=-%cpu', identify the owner, then stop them ('kill <pid>'; escalate to 'kill -9' only if needed)."; }
inject_runaway_process() {
  id carol >/dev/null 2>&1 || { echo "user carol is missing"; return 1; }
  local n
  for n in 1 2; do
    setsid runuser -u carol -- bash -c 'exec -a postproc_job.sh bash -c "while :; do :; done"' </dev/null >/dev/null 2>&1 &
  done
  sleep 1
  pgrep -u carol -f postproc_job.sh >/dev/null
}
check_runaway_process() { ! pgrep -u carol -f postproc_job.sh >/dev/null; }
revert_runaway_process() { pkill -u carol -f postproc_job.sh 2>/dev/null; return 0; }

# ---- scenario: locked-user --------------------------------------------------
ticket_locked_user()   { echo "bob cannot log in on this node, although he is sure his password is correct."; }
solution_locked_user() { echo "bob's account is locked and expired on this node. Check 'passwd -S bob' and 'chage -l bob', then unlock it ('usermod -U bob') and clear the expiry ('usermod -e \"\" bob')."; }
inject_locked_user() {
  id bob >/dev/null 2>&1 || { echo "user bob is missing"; return 1; }
  usermod -L -e 1 bob
}
check_locked_user() {
  local st; st="$(passwd -S bob 2>/dev/null | awk '{print $2}')"
  [ -n "$st" ] && [ "${st:0:1}" != "L" ] && chage -l bob | awk -F': ' '/Account expires/{print $2}' | grep -qi never
}
revert_locked_user() { usermod -U -e "" bob; }

# ---- scenario: hosts-entry --------------------------------------------------
ticket_hosts_entry()   { echo "From this node, '$(cat "$DATA/hosts.target" 2>/dev/null || peer_node)' cannot be reached by name ('Name or service not known'), but the machine is running."; }
solution_hosts_entry() { echo "The node's line is missing from /etc/hosts (name resolution fails). Check 'getent hosts $(cat "$DATA/hosts.target" 2>/dev/null)' and the /etc/hosts file, then add the correct line back."; }
inject_hosts_entry() {
  local t; t="$(peer_node)"; [ -n "$t" ] || { echo "no other node to use"; return 1; }
  echo "$t" > "$DATA/hosts.target"
  cp -a /etc/hosts "$DATA/hosts.orig"
  sed -i -E "/^[0-9.]+[[:space:]]+${t}([[:space:]]|\$)/d" /etc/hosts
}
check_hosts_entry() {
  local t ip; t="$(cat "$DATA/hosts.target")"; ip="$(node_ip "$t")"
  [ "$(getent hosts "$t" | awk '{print $1; exit}')" = "$ip" ]
}
revert_hosts_entry() {
  local t ip; t="$(cat "$DATA/hosts.target")"; ip="$(node_ip "$t")"
  grep -qE "^[0-9.]+[[:space:]]+${t}([[:space:]]|\$)" /etc/hosts || echo "$ip $t" >> /etc/hosts
}

# ---- scenario: nfs-unmounted (compute nodes) --------------------------------
ticket_nfs_unmounted()   { echo "On this node the users' home directories and $LAB_SHARED look empty, and files users saved yesterday are 'gone'."; }
solution_nfs_unmounted() { echo "The NFS share from the login node is not mounted (and its /etc/fstab line was commented out). Check 'findmnt $LAB_SHARED' and /etc/fstab, restore the entry, and mount it again."; }
inject_nfs_unmounted() {
  cp -a /etc/fstab "$DATA/fstab.orig" || return 1
  sed -i '/# hpc-lab mount/s/^/#/' /etc/fstab
  umount -l "$LAB_SHARED"
}
check_nfs_unmounted() { mountpoint -q "$LAB_SHARED" && grep -q '^login:.*# hpc-lab mount' /etc/fstab; }
revert_nfs_unmounted() {
  sed -i '/# hpc-lab mount/s/^#*//' /etc/fstab
  systemctl daemon-reload
  mountpoint -q "$LAB_SHARED" || mount "$LAB_SHARED"
}

# ---- commands ---------------------------------------------------------------
cmd_list() {
  echo "Scenarios (the names reveal the cause; learners should use 'random'):"
  local s
  for s in $SCENARIOS; do printf '  %-18s %s\n' "$s" "$(role_note "$s")"; done
}

active_scenario() { [ -f "$STATE/active" ] && cat "$STATE/active"; }

pick_random() {
  local pool=() s
  for s in $SCENARIOS; do eligible "$s" && pool+=("$s"); done
  [ "${#pool[@]}" -gt 0 ] || die "no scenario fits this node"
  if [ -n "${SEED:-}" ]; then RANDOM="$SEED"; fi
  echo "${pool[$(( RANDOM % ${#pool[@]} ))]}"
}

confirm() {
  [ "${YES:-0}" -eq 1 ] && return 0
  [ -t 0 ] || die "no terminal for the confirmation prompt; add --yes."
  read -r -p "This deliberately breaks part of this lab node ($LAB_NODE). Continue? [y/N] " ans
  case "$ans" in y|Y|yes|YES) return 0 ;; *) echo "Cancelled."; exit 0 ;; esac
}

cmd_inject() {
  need_root; load_release
  local s="$1"
  [ -z "$(active_scenario)" ] || die "a problem is already active on this node. Fix it, or run: sudo inject-fault --revert"
  [ "$s" = random ] && s="$(pick_random)"
  case " $SCENARIOS " in *" $s "*) ;; *) die "unknown scenario '$s'. See: inject-fault --list" ;; esac
  eligible "$s" || die "'$s' cannot run on this node ($(role_note "$s"))."
  confirm
  mkdir -p "$DATA"; chmod 700 "$STATE" "$DATA"
  echo "$s" > "$STATE/active"
  if ! "inject_$(fn "$s")"; then
    echo "inject-fault: could not plant the problem; restoring the node." >&2
    "revert_$(fn "$s")" 2>/dev/null; rm -rf "$STATE"; exit 1
  fi
  "ticket_$(fn "$s")" > "$STATE/ticket"
  "solution_$(fn "$s")" > "$STATE/solution"
  echo
  echo "A problem has been planted on this node. Here is the ticket you received:"
  echo
  sed 's/^/  | /' "$STATE/ticket"
  echo
  echo "Investigate and fix it. Check your progress with: fault-status"
}

cmd_check() {
  need_root; load_release
  local s; s="$(active_scenario)"
  if [ -z "$s" ]; then echo "No problem is active on this node."; exit 2; fi
  if "check_$(fn "$s")" 2>/dev/null; then echo "FIXED: the problem you were given is resolved."; exit 0; fi
  echo "NOT FIXED YET: the problem is still present."; exit 1
}

cmd_ticket() {
  [ -f "$STATE/ticket" ] || { echo "No problem is active on this node."; exit 2; }
  sed 's/^/  | /' "$STATE/ticket"
}

cmd_reveal() {
  need_root
  local s; s="$(active_scenario)"
  [ -n "$s" ] || { echo "No problem is active on this node."; exit 2; }
  echo "Planted problem: $s"
  echo "How to fix it:   $(cat "$STATE/solution" 2>/dev/null)"
}

cmd_revert() {
  need_root; load_release
  local s; s="$(active_scenario)"
  [ -n "$s" ] || { echo "No problem is active on this node."; exit 0; }
  "revert_$(fn "$s")" 2>/dev/null
  if [ -f "$DATA/mounts" ]; then
    while read -r mp; do umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null; rmdir "$mp" 2>/dev/null; done < "$DATA/mounts"
  fi
  rm -rf "$STATE"
  echo "The node is back to normal."
}

# ---- arguments --------------------------------------------------------------
ACTION=""; SCEN=""; YES=0; SEED=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; exit 0 ;;
    --list)    ACTION=list ;;
    --check)   ACTION=check ;;
    --ticket)  ACTION=ticket ;;
    --reveal)  ACTION=reveal ;;
    --revert)  ACTION=revert ;;
    --yes|-y)  YES=1 ;;
    --seed)    shift; SEED="${1:-}"; case "$SEED" in ''|*[!0-9]*) die "--seed needs a number" ;; esac ;;
    -*)        die "unknown option $1 (see --help)" ;;
    *)         SCEN="$1" ;;
  esac
  shift
done

case "$ACTION" in
  list)   cmd_list ;;
  check)  cmd_check ;;
  ticket) cmd_ticket ;;
  reveal) cmd_reveal ;;
  revert) cmd_revert ;;
  *)      [ -n "$SCEN" ] || { awk 'NR>1 && /^#/ {print; next} NR>1 {exit}' "$0"; exit 1; }; cmd_inject "$SCEN" ;;
esac
