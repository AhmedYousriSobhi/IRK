#!/usr/bin/env bash
# provision-base.sh - base setup for an HPC lab VM (Rocky Linux 9; other RHEL 9 clones are
# accepted but untested).
#
# Run by the Vagrantfile as root, with these variables set:
#   LAB_NODE   node name (login, compute1, ...)      LAB_IP     this node's private IP
#   LAB_ROLE   login | compute                       LAB_NODES  "login=IP,compute1=IP,..."
#   LAB_PASSWORD (optional) password for the lab user accounts
#
# What it does: hostname and /etc/hosts, base packages, time sync, firewall and SELinux
# settings for NFS homes, SSH password login for the lab users, shared storage (NFS from
# the login node), lab user accounts, and the lab helper tools.
# It does NOT install Slurm (learners do that in chapter 7) and does NOT create SSH keys
# between nodes (learners do that in chapter 3).
#
# Safe to run more than once.
set -euo pipefail

NODE_NAME="${LAB_NODE:-}"
NODE_IP="${LAB_IP:-}"
NODE_ROLE="${LAB_ROLE:-}"
NODES="${LAB_NODES:-}"
LAB_PASSWORD="${LAB_PASSWORD:-hpclab}"
LOGIN_NAME="login"
SHARED="/shared"
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAB_ROOT="$(dirname "$CORE_DIR")"   # core/ and modules/ are staged side by side
RELEASE_FILE="/etc/hpc-lab-release"

# Lab accounts: same UID/GID on every node (there is no LDAP in the lab).
GROUPS_TO_CREATE="hpc-users:2000 proj-a:2100"
USERS_TO_CREATE="alice:2001:proj-a bob:2002:proj-a carol:2003:"

log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(date +%H:%M:%S)" "$*" >&2; exit 1; }
trap 'die "failed at line $LINENO (command: $BASH_COMMAND)"' ERR

# ---- validate input ---------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "run as root"
[ -n "$NODE_NAME" ] && [ -n "$NODE_IP" ] || die "LAB_NODE and LAB_IP must be set"
case "$NODE_ROLE" in login|compute) ;; *) die "LAB_ROLE must be 'login' or 'compute'" ;; esac
[ -n "$NODES" ] || die "LAB_NODES must be set (name=ip,name=ip,...)"
SUBNET="${NODE_IP%.*}.0/24"

. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *rhel*|*fedora*|*rocky*|*almalinux*|*centos*) ;;
  *) die "this lab needs a RHEL-family OS (Rocky/Alma), found: ${PRETTY_NAME:-unknown}" ;;
esac
log "Provisioning $NODE_NAME ($NODE_ROLE, $NODE_IP) on ${PRETTY_NAME:-RHEL family}"

# ---- hostname and /etc/hosts ------------------------------------------------
hostnamectl set-hostname "$NODE_NAME"
# Some boxes map the node's own name to a loopback address; that breaks cluster software later.
sed -i -E "/^127\.0\.[01]\.1[[:space:]]+${NODE_NAME}([[:space:]]|\$)/d" /etc/hosts
sed -i '/# BEGIN hpc-lab/,/# END hpc-lab/d' /etc/hosts
{
  echo "# BEGIN hpc-lab"
  IFS=',' read -ra pairs <<< "$NODES"
  for p in "${pairs[@]}"; do echo "${p#*=} ${p%%=*}"; done
  echo "# END hpc-lab"
} >> /etc/hosts
log "hostname and /etc/hosts set"

# ---- swap: a 1 GB VM needs a safety net while installs run -----------------
if [ -z "$(swapon --show --noheadings)" ]; then
  dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  restorecon /swapfile 2>/dev/null || true
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap defaults 0 0' >> /etc/fstab
  log "1 GiB swap file enabled"
fi

# ---- OpenSSH first: boxes can be older than the repositories -----------------
# Installing the packages below upgrades openssl-libs. An older OpenSSH that is already
# running then drops every new connection (reset before the banner), so the node looks
# provisioned but cannot be reached. Upgrading OpenSSH first keeps sshd and its libraries
# in step. sshd is restarted (not reloaded) so it runs the new binary; the current
# session survives the restart.
log "upgrading OpenSSH (needs internet access)"
dnf -y upgrade openssh openssh-clients openssh-server >/dev/null
systemctl restart sshd

# ---- packages: only what the node does not have yet --------------------------
# 'dnf install' also upgrades packages that are already installed, so naming the whole list
# on every node pulls in dozens of unrelated upgrades. Install just the missing ones.
PACKAGES="nfs-utils chrony cronie rsync tar gzip vim-enhanced nano tree lsof strace psmisc \
  procps-ng bind-utils iproute iputils net-tools bash-completion man-db quota python3"
missing=""
for p in $PACKAGES; do
  rpm -q "$p" >/dev/null 2>&1 || missing="$missing $p"
done
if [ -n "$missing" ]; then
  log "installing packages:$missing (needs internet access)"
  dnf -y --setopt=install_weak_deps=False install $missing >/dev/null
fi
# htop is the only package that needs EPEL
if ! rpm -q htop >/dev/null 2>&1; then
  { dnf -y --setopt=install_weak_deps=False install epel-release &&
    dnf -y --setopt=install_weak_deps=False install htop; } >/dev/null ||
    warn "htop not available from the repositories (continuing)"
fi

# ---- scheduling service (also used by the troubleshooting scenarios) --------
systemctl enable --now crond >/dev/null 2>&1 || warn "could not enable crond"

# ---- time sync (cluster authentication breaks when clocks differ) -----------
systemctl enable --now chronyd
log "chronyd enabled"

# ---- SELinux and firewall ---------------------------------------------------
if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce)" != "Disabled" ]; then
  setsebool -P use_nfs_home_dirs 1   # lets users log in with NFS-mounted home directories
  log "SELinux: use_nfs_home_dirs enabled"
fi
if systemctl is-active --quiet firewalld; then
  firewall-cmd --permanent --zone=trusted --add-source="$SUBNET" >/dev/null 2>&1 || true
  firewall-cmd --reload >/dev/null
  log "firewalld: $SUBNET trusted (cluster traffic); firewalld stays enabled"
fi

# ---- SSH: allow password login for the lab users ----------------------------
# Learners set up key-based login themselves in chapter 3, which needs password login first.
# The file name sorts first so it wins over cloud-image drop-ins (sshd uses the first value found).
if grep -qE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config.d/' /etc/ssh/sshd_config; then
  mkdir -p /etc/ssh/sshd_config.d
  printf 'PasswordAuthentication yes\n' > /etc/ssh/sshd_config.d/01-lab.conf
  sshd -t && systemctl reload sshd
  log "sshd: password authentication enabled for lab users"
else
  warn "sshd_config has no Include for sshd_config.d; password login not changed"
fi

# ---- shared storage (NFS from the login node) -------------------------------
if [ "$NODE_ROLE" = "login" ]; then
  mkdir -p "$SHARED/home" "$SHARED/scratch" "$SHARED/project/proj-a"
  chmod 755 "$SHARED" "$SHARED/home" "$SHARED/project"
  chmod 1777 "$SHARED/scratch"
  sed -i '\|# hpc-lab export|d' /etc/exports
  echo "$SHARED $SUBNET(rw,sync,no_subtree_check) # hpc-lab export" >> /etc/exports
  systemctl enable --now nfs-server
  exportfs -ra
  log "NFS: exporting $SHARED to $SUBNET"
else
  mkdir -p "$SHARED"
  sed -i '\|# hpc-lab mount|d' /etc/fstab
  echo "${LOGIN_NAME}:${SHARED} ${SHARED} nfs defaults,_netdev 0 0 # hpc-lab mount" >> /etc/fstab
  # Some boxes ship with remote-fs.target disabled, which silently skips every _netdev mount
  # at boot. Without this, /shared is gone after the first reboot.
  systemctl enable remote-fs.target >/dev/null 2>&1
  systemctl daemon-reload
  if ! mountpoint -q "$SHARED"; then
    ok=0
    for i in $(seq 1 60); do   # up to ~5 minutes: the login node may still be installing
      if mount "$SHARED" 2>/dev/null; then ok=1; break; fi
      [ $(( (i - 1) % 6 )) -eq 0 ] && log "waiting for ${LOGIN_NAME}:${SHARED} (attempt $i/60)"
      sleep 5
    done
    [ "$ok" -eq 1 ] || die "cannot mount ${LOGIN_NAME}:${SHARED}. Check that the VMs can reach each other (private network) and that '$LOGIN_NAME' is up."
  fi
  log "NFS: $SHARED mounted from $LOGIN_NAME"
fi

# ---- lab groups and users ---------------------------------------------------
for entry in $GROUPS_TO_CREATE; do
  g="${entry%%:*}"; gid="${entry##*:}"
  getent group "$g" >/dev/null || groupadd -g "$gid" "$g"
done
for entry in $USERS_TO_CREATE; do
  IFS=':' read -r u uid extra <<< "$entry"
  if ! id -u "$u" >/dev/null 2>&1; then
    if [ "$NODE_ROLE" = "login" ]; then
      useradd -u "$uid" -g hpc-users ${extra:+-G "$extra"} -d "$SHARED/home/$u" -m -s /bin/bash "$u"
    else
      useradd -u "$uid" -g hpc-users ${extra:+-G "$extra"} -d "$SHARED/home/$u" -M -s /bin/bash "$u"
    fi
  fi
  echo "$u:$LAB_PASSWORD" | chpasswd
done
if [ "$NODE_ROLE" = "login" ]; then
  chown root:proj-a "$SHARED/project/proj-a"
  chmod 2770 "$SHARED/project/proj-a"
fi
log "lab users ready (alice, bob, carol); password is the lab password"

# ---- lab helper tools -------------------------------------------------------
# Tools come from core/bin and from every module's bin/ (the .sh extension is dropped).
tools=0
for f in "$CORE_DIR"/bin/* "$LAB_ROOT"/modules/*/bin/*; do
  [ -f "$f" ] || continue
  install -m 0755 "$f" "/usr/local/bin/$(basename "${f%.sh}")"
  tools=$((tools + 1))
done
log "installed $tools lab tools into /usr/local/bin"

# ---- let 'sudo <lab tool>' find /usr/local/bin (RHEL's sudo ignores it by default) --
printf 'Defaults secure_path = /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' > /etc/sudoers.d/90-lab-path
chmod 440 /etc/sudoers.d/90-lab-path
if ! visudo -cf /etc/sudoers.d/90-lab-path >/dev/null 2>&1; then
  rm -f /etc/sudoers.d/90-lab-path
  warn "could not install the sudo path setting; use the full path: sudo /usr/local/bin/<tool>"
fi

# ---- record what this node is (read by lab-verify) --------------------------
{
  echo "LAB_NODE=$NODE_NAME"
  echo "LAB_ROLE=$NODE_ROLE"
  echo "LAB_IP=$NODE_IP"
  echo "LAB_NODES=$NODES"
  echo "LAB_SUBNET=$SUBNET"
  echo "LAB_SHARED=$SHARED"
  echo "LAB_USERS=alice:2001,bob:2002,carol:2003"
  echo "LAB_PROVISIONED=$(date -Is)"
} > "$RELEASE_FILE"

log "Base provisioning complete for $NODE_NAME. Check with: lab-verify"
