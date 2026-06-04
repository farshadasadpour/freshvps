# freshvps

A simple VPS bootstrap script for Debian/Ubuntu-based systems.

## Usage

### Option 1: With SSH Key (Recommended)

Provide your SSH public key **before running the script**.
This works when the shell running the command has access to the key file.

```bash
SSH_PUBKEY="$(cat ~/.ssh/id_rsa.pub)" sudo -E bash bootstrap-vps.sh
```

Or via curl:

```bash
SSH_PUBKEY="$(cat ~/.ssh/id_rsa.pub)" sudo -E bash -c 'curl -fsSL https://raw.githubusercontent.com/farshadasadpour/freshvps/main/bootstrap-vps.sh | bash'
```

If you want a custom SSH user or custom port:

```bash
SSH_PUBKEY="$(cat ~/.ssh/id_rsa.pub)" SSH_USER=sumiroz SSH_PORT=2825 sudo -E bash bootstrap-vps.sh
```

Or via curl:

```bash
SSH_PUBKEY="$(cat ~/.ssh/id_rsa.pub)" SSH_USER=sumiroz SSH_PORT=2825 sudo -E bash -c 'curl -fsSL https://raw.githubusercontent.com/farshadasadpour/freshvps/main/bootstrap-vps.sh | bash'
```

> Note: `SSH_PUBKEY=$(cat ~/.ssh/id_rsa.pub)` reads the key from the machine where you run the command.
If you run this from a local laptop, it uses the local key file. If you run it on the VPS and that file is missing, it will fail.

### Option 2: Interactive Prompt (Local Terminal Only)

If running directly on the VPS (not via curl pipe):

```bash
sudo bash bootstrap-vps.sh
```

The script will prompt for your SSH public key. Paste your local public key into the prompt.

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

## SSH Monitoring with Telegram

A lightweight monitor script is included in `monitor-ssh-telegram.sh`.
It sends Telegram notifications for:

- successful SSH logins
- fail2ban bans

### Usage

```bash
TELEGRAM_API_TOKEN=your_http_api_token ./monitor-ssh-telegram.sh
```

Or via curl and install the service automatically:

```bash
TELEGRAM_API_TOKEN=your_http_api_token sudo -E bash -c 'curl -fsSL https://raw.githubusercontent.com/farshadasadpour/freshvps/main/monitor-ssh-telegram.sh | bash -s -- --install'
```

If the script does not discover your chat ID automatically, send a message to your bot and rerun with `TELEGRAM_CHAT_ID` set.

If you already know your chat ID, set it explicitly:

```bash
TELEGRAM_API_TOKEN=your_http_api_token TELEGRAM_CHAT_ID=your_chat_id ./monitor-ssh-telegram.sh
```

The script also supports `TELEGRAM_BOT_TOKEN` as an alias for legacy usage.

### Systemd service

The script can install itself and create the systemd unit automatically.

1. Run the install command with your Telegram values:

```bash
TELEGRAM_API_TOKEN=your_http_api_token TELEGRAM_CHAT_ID=your_chat_id sudo -E bash monitor-ssh-telegram.sh --install
```

Or use the curl one-liner to do the same from the repo:

```bash
TELEGRAM_API_TOKEN=your_http_api_token sudo -E bash -c 'curl -fsSL https://raw.githubusercontent.com/farshadasadpour/freshvps/main/monitor-ssh-telegram.sh | bash -s -- --install'
```

2. The script will copy itself to `/usr/local/bin/monitor-ssh-telegram.sh`, create `/etc/systemd/system/monitor-ssh-telegram.service`, and enable/start the service.

The generated systemd unit looks like this:

```ini
[Unit]
Description=SSH and fail2ban Telegram monitor
After=network-online.target syslog.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/monitor-ssh-telegram.sh
Restart=always
RestartSec=10
EnvironmentFile=-/etc/default/monitor-ssh-telegram
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

The environment file used by the service is `/etc/default/monitor-ssh-telegram`.
Create it manually if needed:

```bash
sudo tee /etc/default/monitor-ssh-telegram >/dev/null <<'EOF'
TELEGRAM_API_TOKEN=your_http_api_token
TELEGRAM_CHAT_ID=your_chat_id
EOF
sudo chmod 600 /etc/default/monitor-ssh-telegram
```

If the service still does not exist, run this manual installation instead:

```bash
sudo cp monitor-ssh-telegram.sh /usr/local/bin/monitor-ssh-telegram.sh
sudo cp monitor-ssh-telegram.service /etc/systemd/system/monitor-ssh-telegram.service
sudo systemctl daemon-reload
sudo systemctl enable --now monitor-ssh-telegram.service
```

3. Check the status:

```bash
sudo systemctl status monitor-ssh-telegram.service
```

If using a bot token only, send a message to the bot first so chat discovery works, or set `TELEGRAM_CHAT_ID` explicitly.

### Requirements

- `curl`
- access to `/var/log/auth.log`
- access to `/var/log/fail2ban.log`

### Notes

- This is intentionally simple and resource-light.
- It reads new log lines and sends notifications only for SSH success and fail2ban bans.
