#!/usr/bin/env bash

set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Use sudo or login as root."
  exit 1
fi

SSH_PUBKEY="${SSH_PUBKEY:-}"
if [ -z "$SSH_PUBKEY" ]; then
  if [ -t 0 ]; then
    echo "[!] IMPORTANT: SSH root key needed for secure access."
    echo "[+] Enter public SSH key for root access (or press Enter to skip):"
    read -r SSH_PUBKEY || true
  else
    echo "[!] WARNING: No SSH_PUBKEY environment variable provided."
    echo "[!] To set a root SSH key, run:"
    echo "[!]   SSH_PUBKEY=\"\$(cat ~/.ssh/id_rsa.pub)\" sudo bash bootstrap-vps.sh"
    echo "[!] Continuing without SSH key setup. Access via VNC only."
  fi
fi

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
  fail2ban \
  ufw \
  unattended-upgrades \
  auditd \
  audispd-plugins \
  sysstat

###############################################################################
# OH MY ZSH
###############################################################################

echo "[+] Installing Oh My Zsh"

export RUNZSH=no
export CHSH=no

if [ ! -d "/root/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

cat >/root/.zshrc <<'EOF'
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

chsh -s /usr/bin/zsh root || true

###############################################################################
# SSH HARDENING
###############################################################################

echo "[+] Configuring SSH"

mkdir -p /etc/ssh/sshd_config.d

cat >/etc/ssh/sshd_config.d/99-security.conf <<'EOF'
PermitRootLogin prohibit-password

PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

PubkeyAuthentication yes

MaxAuthTries 3
LoginGraceTime 30

X11Forwarding no
AllowAgentForwarding no

ClientAliveInterval 300
ClientAliveCountMax 2
EOF

if sshd -t; then
  echo "[+] SSH config syntax OK"
  systemctl enable --now ssh
else
  echo "[!] SSH config invalid, aborting."
  exit 1
fi

echo "[+] Configuring SSH authorized_keys"
mkdir -p /root/.ssh
chmod 700 /root/.ssh
if [ -n "$SSH_PUBKEY" ]; then
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
  if ! grep -Fxq "$SSH_PUBKEY" /root/.ssh/authorized_keys 2>/dev/null; then
    printf '%s\n' "$SSH_PUBKEY" >> /root/.ssh/authorized_keys
    echo "[+] SSH public key added to /root/.ssh/authorized_keys"
  fi
else
  echo "[!] Skipping SSH key setup (no SSH_PUBKEY provided)."
  touch /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

mkdir -p /root/.docker
chmod 700 /root/.docker
if [ -d /root/.docker/config.json ]; then
  rm -rf /root/.docker/config.json
fi
if [ ! -f /root/.docker/config.json ]; then
  printf '{}\n' > /root/.docker/config.json
  chmod 600 /root/.docker/config.json
fi

###############################################################################
# FIREWALL
###############################################################################

echo "[+] Configuring UFW"

ufw --force reset

ufw default deny incoming
ufw default allow outgoing

ufw allow 22/tcp

# Uncomment if needed
# ufw allow 80/tcp
# ufw allow 443/tcp
ufw --force enable

###############################################################################
# FAIL2BAN
###############################################################################

echo "[+] Configuring Fail2Ban"

cat >/etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
Bantime = 24h
Findtime = 15m
Maxretry = 5

[sshd]
enabled = true
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
-w /etc/passwd -p wa
-w /etc/group -p wa
-w /etc/shadow -p wa
-w /etc/sudoers -p wa
-w /usr/bin/sudo -p x
EOF

systemctl enable auditd
systemctl restart auditd

###############################################################################
# SWAP (2G)
###############################################################################

if [ ! -f /swapfile ]; then
  echo "[+] Creating swap"
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

###############################################################################
# SYSCTL TUNING
###############################################################################

echo "[+] Applying sysctl tuning"

cat >/etc/sysctl.d/99-custom.conf <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50

net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.tcp_syncookies=1

net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1

kernel.kptr_restrict=2
kernel.dmesg_restrict=1
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
# RELOAD SERVICES
###############################################################################

echo "[+] Reloading SSH"
systemctl reload ssh || systemctl restart ssh

cat <<'EOF'

==========================================
 VPS Bootstrap Completed Successfully
==========================================

Installed:
 vim, curl, wget, git, jq
 htop, btop, tmux, screen
 tcpdump, dnsutils, traceroute
 zsh + oh-my-zsh
 fail2ban, ufw, auditd
 unattended-upgrades

Root login: SSH keys only
Password login: disabled

EOF
