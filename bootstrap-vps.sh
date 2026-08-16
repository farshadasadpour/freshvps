#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# BOOTSTRAP-VPS.SH
# Hardens a fresh Debian/Ubuntu VPS with SSH key auth, UFW, Fail2Ban,
# auditd, sysctl tuning, and more.
#
# Usage:
#   SSH_PUBKEY="$(cat ~/.ssh/id_rsa.pub)" sudo bash bootstrap-vps.sh
#
# Optional env vars:
#   SSH_USER        — admin username to create        (default: code)
#   SSH_PORT        — SSH port to listen on            (default: 2825)
#   SWAP_SIZE       — swap file size, G suffix         (default: 2G)
#   ENABLE_FIREWALL — configure UFW firewall (1=yes)   (default: 0)
###############################################################################

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Use sudo or login as root."
  exit 1
fi

SSH_PUBKEY="${SSH_PUBKEY:-}"
SSH_USER="${SSH_USER:-code}"
SSH_PORT="${SSH_PORT:-2825}"
SWAP_SIZE="${SWAP_SIZE:-2G}"
ENABLE_FIREWALL="${ENABLE_FIREWALL:-0}"

# ── Collect SSH public key interactively if not provided ─────────────────────
if [ -z "$SSH_PUBKEY" ]; then
  if [ -t 0 ]; then
    echo "[!] IMPORTANT: SSH public key needed for secure access."
    echo "[+] Enter your SSH public key:"
    read -r SSH_PUBKEY
  fi
fi

if [ -z "$SSH_PUBKEY" ]; then
  echo "[!] ERROR: No SSH public key provided."
  echo "[!] Set SSH_PUBKEY=\"\$(cat ~/.ssh/id_rsa.pub)\" before running the script."
  echo "[!] Example: SSH_PUBKEY=\"\$(cat ~/.ssh/id_rsa.pub)\" sudo bash bootstrap-vps.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

###############################################################################
# SYSTEM UPDATE
###############################################################################

echo "[+] Updating system"
apt update
apt upgrade -y

###############################################################################
# COMMON TOOLS
###############################################################################

echo "[+] Installing common tools"
apt install -y \
  vim \
  nano \
  curl \
  wget \
  git \
  unzip \
  zip \
  jq \
  tree \
  htop \
  btop \
  tmux \
  screen \
  net-tools \
  dnsutils \
  traceroute \
  tcpdump \
  lsof \
  rsync \
  ca-certificates \
  gnupg \
  software-properties-common \
  apt-transport-https \
  build-essential \
  bash-completion \
  zsh \
  chrony \
  fail2ban \
  unattended-upgrades \
  auditd \
  audispd-plugins \
  sysstat \
  python3.12-venv

###############################################################################
# TIME SYNC
###############################################################################

echo "[+] Enabling NTP time sync"
systemctl enable chrony
systemctl start chrony
timedatectl set-ntp true

###############################################################################
# OH MY ZSH  (root + SSH_USER)
###############################################################################

echo "[+] Installing Oh My Zsh"

export RUNZSH=no
export CHSH=no

_install_ohmyzsh_for() {
  local target_home="$1"
  local target_user="$2"

  if [ ! -d "$target_home/.oh-my-zsh" ]; then
    if [ "$target_user" = "root" ]; then
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    else
      sudo -u "$target_user" sh -c 'cd "$HOME" && sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
    fi
  fi

  cat >"$target_home/.zshrc" <<'EOF'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"

plugins=(
  git
  docker
  kubectl
)

source $ZSH/oh-my-zsh.sh

alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias k='kubectl'
EOF

  chown "$target_user:$target_user" "$target_home/.zshrc"
}

_install_ohmyzsh_for /root root

###############################################################################
# SSH USER SETUP
###############################################################################

echo "[+] Creating sudo user '$SSH_USER'"

if ! id "$SSH_USER" >/dev/null 2>&1; then
  useradd -m -s /usr/bin/zsh -G sudo "$SSH_USER"
fi

# Passwordless sudo
cat >/etc/sudoers.d/$SSH_USER <<EOF
$SSH_USER ALL=(ALL) NOPASSWD:ALL
EOF
chmod 440 /etc/sudoers.d/$SSH_USER
visudo -cf /etc/sudoers.d/$SSH_USER >/dev/null 2>&1 || {
  echo "[!] Invalid sudoers file for $SSH_USER"
  exit 1
}

# SSH authorized_keys
mkdir -p /home/$SSH_USER/.ssh
chmod 700 /home/$SSH_USER/.ssh
chown $SSH_USER:$SSH_USER /home/$SSH_USER/.ssh

touch /home/$SSH_USER/.ssh/authorized_keys
chmod 600 /home/$SSH_USER/.ssh/authorized_keys
chown $SSH_USER:$SSH_USER /home/$SSH_USER/.ssh/authorized_keys

if ! grep -Fxq "$SSH_PUBKEY" /home/$SSH_USER/.ssh/authorized_keys 2>/dev/null; then
  printf '%s\n' "$SSH_PUBKEY" >> /home/$SSH_USER/.ssh/authorized_keys
  echo "[+] SSH public key added for '$SSH_USER'"
fi

# Install Oh My Zsh for the new user too
_install_ohmyzsh_for /home/$SSH_USER $SSH_USER

###############################################################################
# SSH HARDENING  (validate config BEFORE restarting)
###############################################################################

echo "[+] Configuring SSH"

mkdir -p /etc/ssh/sshd_config.d

cat >/etc/ssh/sshd_config.d/99-security.conf <<EOF
Port $SSH_PORT
PermitRootLogin no
PasswordAuthentication no
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no

MaxAuthTries 3
LoginGraceTime 30

X11Forwarding no
AllowAgentForwarding no

ClientAliveInterval 300
ClientAliveCountMax 2
AllowUsers $SSH_USER
EOF

# ── Validate BEFORE touching the running daemon ───────────────────────────────
if sshd -t; then
  echo "[+] SSH config syntax OK"
  systemctl enable --now ssh
  systemctl restart ssh
  if ! systemctl is-active --quiet ssh; then
    echo "[!] SSH service failed to start:"
    systemctl status ssh --no-pager || true
    journalctl -u ssh --no-pager -n 20 || true
    exit 1
  fi
  if ! ss -tlnp | grep -qE "[:.]${SSH_PORT}\\b"; then
    echo "[!] SSH is not listening on port $SSH_PORT — check config"
    ss -tlnp | grep -E "[:.]${SSH_PORT}\\b" || true
    exit 1
  fi
  echo "[+] SSH is listening on port $SSH_PORT"
else
  echo "[!] SSH config invalid — aborting before restart to avoid lockout."
  exit 1
fi

###############################################################################
# FIREWALL (optional, default off)
###############################################################################

if [ "${ENABLE_FIREWALL:-0}" = "1" ]; then
  echo "[+] Installing ufw"
  apt install -y ufw

echo "[+] Configuring UFW"

  sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw

  ufw --force reset

ufw default deny incoming
  ufw default allow outgoing

  ufw allow $SSH_PORT/tcp comment 'SSH'

  # Uncomment if needed:
  # ufw allow 80/tcp  comment 'HTTP'
  # ufw allow 443/tcp comment 'HTTPS'
  ufw --force enable
fi

echo "[+] UFW rules applied (IPv4 + IPv6)"

###############################################################################
# FAIL2BAN
###############################################################################

echo "[+] Configuring Fail2Ban"

cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 24h
findtime = 15m
maxretry = 5

[sshd]
enabled = true
port    = $SSH_PORT
EOF

systemctl enable fail2ban
systemctl restart fail2ban

###############################################################################
# AUTO SECURITY UPDATES
###############################################################################

echo "[+] Enabling unattended upgrades"

systemctl enable unattended-upgrades
DEBIAN_FRONTEND=noninteractive dpkg-reconfigure -f noninteractive unattended-upgrades

###############################################################################
# AUDITD
###############################################################################

echo "[+] Configuring auditd"

cat >/etc/audit/rules.d/custom.rules <<'EOF'
-w /etc/passwd   -p wa -k identity
-w /etc/group    -p wa -k identity
-w /etc/shadow   -p wa -k identity
-w /etc/sudoers  -p wa -k sudoers
-w /usr/bin/sudo -p x  -k sudoers
EOF

systemctl enable auditd
systemctl restart auditd

###############################################################################
# SWAP
###############################################################################

if [ ! -f /swapfile ]; then
echo "[+] Creating ${SWAP_SIZE} swap file"
  dd if=/dev/zero of=/swapfile bs=1M count="$(( ${SWAP_SIZE%G} * 1024 ))" status=progress
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >>/etc/fstab
fi

###############################################################################
# SYSCTL TUNING
###############################################################################

echo "[+] Applying sysctl tuning"

cat >/etc/sysctl.d/99-custom.conf <<'EOF'
# Memory
vm.swappiness=10
vm.vfs_cache_pressure=50

# Network performance
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_syncookies=1

# Reverse path filtering (anti-spoofing)
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1

net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0

net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0

net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_source_route=0

net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.tcp_rfc1337=1

# Kernel hardening
kernel.kptr_restrict=2
kernel.dmesg_restrict=1
kernel.randomize_va_space=2
kernel.yama.ptrace_scope=2

fs.protected_hardlinks=1
fs.protected_symlinks=1
EOF

sysctl --system

###############################################################################
# JOURNAL LIMITS
###############################################################################

echo "[+] Restricting journal size"

mkdir -p /etc/systemd/journald.conf.d

cat >/etc/systemd/journald.conf.d/size.conf <<'EOF'
[Journal]
SystemMaxUse=500M
RuntimeMaxUse=100M
EOF

systemctl restart systemd-journald

###############################################################################
# CLEANUP
###############################################################################

echo "[+] Cleaning up"

apt autoremove -y
apt autoclean -y

###############################################################################
# FINAL RELOAD
###############################################################################

systemctl reload ssh || systemctl restart ssh

###############################################################################
# SUMMARY
###############################################################################

UFW_STATUS="not configured (ENABLE_FIREWALL=0)"
if [ "${ENABLE_FIREWALL:-0}" = "1" ]; then
  UFW_STATUS="default deny (IPv4 + IPv6)"
fi

TOOLS_SEC="fail2ban, auditd, chrony"
if [ "${ENABLE_FIREWALL:-0}" = "1" ]; then
  TOOLS_SEC="fail2ban, ufw, auditd, chrony"
fi

cat <<EOF

==========================================
 VPS Bootstrap Completed Successfully
==========================================

System:
  Swap ............. $SWAP_SIZE at /swapfile
  Time sync ........ chrony (NTP enabled)
  Auto updates ..... unattended-upgrades

Security:
  SSH user ......... $SSH_USER  (port $SSH_PORT)
  Root SSH login ... disabled
  Password login ... disabled
  UFW .............. $UFW_STATUS
  Fail2Ban ......... enabled (ban 24h after 5 attempts)
  Auditd ........... watching passwd, shadow, sudoers
  SSH config ....... validated before restart

Tools installed:
  vim, nano, curl, wget, git, jq, tree
  htop, btop, tmux, screen
  tcpdump, dnsutils, traceroute, lsof
  zsh + oh-my-zsh  (root only)
$TOOLS_SEC
  unattended-upgrades, sysstat

Next steps:
  ssh -p $SSH_PORT $SSH_USER@<your-server-ip>

==========================================
EOF
