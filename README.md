# freshvps

A simple VPS bootstrap script for Debian/Ubuntu-based systems.

## Usage

Run the script as root on a fresh VPS:

```bash
sudo bash bootstrap-vps.sh
```

Or fetch and run it directly on the VPS with `curl`:

```bash
curl -fsSL https://raw.githubusercontent.com/farshadasadpour/freshvps/main/bootstrap-vps.sh | sudo bash
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
