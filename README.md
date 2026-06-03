# freshvps

A simple VPS bootstrap script for Debian/Ubuntu-based systems.

## Usage

### Option 1: With SSH Key (Recommended)

Provide your SSH public key **before running the script**:

```bash
SSH_PUBKEY="$(cat ~/.ssh/id_rsa.pub)" sudo bash bootstrap-vps.sh
```

Or via curl:

```bash
SSH_PUBKEY="$(cat ~/.ssh/id_rsa.pub)" bash -c 'curl -fsSL https://raw.githubusercontent.com/farshadasadpour/freshvps/main/bootstrap-vps.sh | sudo bash'
```

### Option 2: Interactive Prompt (Local Terminal Only)

If running directly on the VPS (not via curl pipe):

```bash
sudo bash bootstrap-vps.sh
```

The script will prompt for your SSH public key.

### Option 3: Via VNC Without SSH Setup

If setting up via VNC and no SSH key:

```bash
curl -fsSL https://raw.githubusercontent.com/farshadasadpour/freshvps/main/bootstrap-vps.sh | sudo bash
```

⚠️ **WARNING**: This skips SSH key setup. You will need to manually add your key later via VNC:

```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
echo "your-public-key-here" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

The script performs:

- system update and upgrade
- installs common tools
- installs Oh My Zsh for root
- hardens SSH
- configures UFW firewall
- enables Fail2Ban and auditd
- enables unattended upgrades
- adds 2 GB swap
- applies sysctl and journald tuning
