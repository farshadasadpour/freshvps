#!/usr/bin/env bash

set -euo pipefail

# Minimal SSH monitoring script for Debian/Ubuntu.
# Requires a Telegram bot token and chat id.
# Sends a Telegram message when an SSH login succeeds
# and when fail2ban bans an IP.

SCRIPT_PATH="$(readlink -f "$0")"
DEST_BIN="/usr/local/bin/monitor-ssh-telegram.sh"
UNIT_PATH="/etc/systemd/system/monitor-ssh-telegram.service"
ENV_FILE="/etc/default/monitor-ssh-telegram"

install_service() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This command must be run as root to install the service." >&2
    exit 1
  fi

  echo "[+] Installing monitor to $DEST_BIN"
  mkdir -p "$(dirname "$DEST_BIN")"
  cp "$SCRIPT_PATH" "$DEST_BIN"
  chmod 755 "$DEST_BIN"

  echo "[+] Creating systemd service at $UNIT_PATH"
  cat >"$UNIT_PATH" <<'EOF'
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
EOF
  chmod 644 "$UNIT_PATH"

  if [ -n "${TELEGRAM_API_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "[+] Writing default environment file to $ENV_FILE"
    mkdir -p "$(dirname "$ENV_FILE")"
    cat >"$ENV_FILE" <<EOF
TELEGRAM_API_TOKEN=${TELEGRAM_API_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
EOF
    chmod 600 "$ENV_FILE"
  elif [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    echo "[+] Writing default environment file to $ENV_FILE"
    mkdir -p "$(dirname "$ENV_FILE")"
    cat >"$ENV_FILE" <<EOF
TELEGRAM_API_TOKEN=${TELEGRAM_BOT_TOKEN}
TELEGRAM_CHAT_ID=${TELEGRAM_CHAT_ID}
EOF
    chmod 600 "$ENV_FILE"
  else
    echo "[!] TELEGRAM_API_TOKEN or TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID not set. Create $ENV_FILE manually."
  fi

  systemctl daemon-reload
  systemctl enable --now monitor-ssh-telegram.service
  echo "[+] Service installed and started."
  exit 0
}

if [ "${1:-}" = "--install" ]; then
  install_service
fi

if [ -f "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

TELEGRAM_API_TOKEN="${TELEGRAM_API_TOKEN:-${TELEGRAM_BOT_TOKEN:-}}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"
AUTH_LOG="${AUTH_LOG:-/var/log/auth.log}"
FAIL2BAN_LOG="${FAIL2BAN_LOG:-/var/log/fail2ban.log}"

discover_chat_id() {
  echo "[+] Attempting to discover Telegram chat_id from getUpdates..."
  local resp
  resp=$(curl -sS "https://api.telegram.org/bot${TELEGRAM_API_TOKEN}/getUpdates?limit=5") || return 1
  if [[ "$resp" =~ "ok":true ]]; then
    if [[ "$resp" =~ \"chat\"[^\"]*\"id\"[[:space:]]*:[[:space:]]*([0-9]+) ]]; then
      TELEGRAM_CHAT_ID="${BASH_REMATCH[1]}"
      echo "[+] Discovered TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID"
      return 0
    fi
  fi
  return 1
}

if [ -z "$TELEGRAM_API_TOKEN" ]; then
  cat <<EOF >&2
Usage: TELEGRAM_API_TOKEN=your_bot_token [TELEGRAM_CHAT_ID=your_chat_id] ./monitor-ssh-telegram.sh

Environment variables:
  TELEGRAM_API_TOKEN  Your Telegram HTTP API token
  TELEGRAM_CHAT_ID    Optional if the bot already has a message from your chat
  AUTH_LOG            Optional auth log path (default: /var/log/auth.log)
  FAIL2BAN_LOG        Optional fail2ban log path (default: /var/log/fail2ban.log)

If TELEGRAM_CHAT_ID is not set, the script will try to discover it from getUpdates.
EOF
  exit 1
fi

if [ -z "$TELEGRAM_CHAT_ID" ]; then
  if ! discover_chat_id; then
    cat <<EOF >&2
[!] TELEGRAM_CHAT_ID is not set and could not be discovered from getUpdates.
Send a message to your bot first, then rerun this script.
You can also get the chat_id manually by calling:
  curl -sS https://api.telegram.org/bot${TELEGRAM_API_TOKEN}/getUpdates
EOF
    exit 1
  fi
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "[!] curl is required" >&2
  exit 1
fi

send_telegram() {
  local message="$1"
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_API_TOKEN}/sendMessage" \
    --data chat_id="$TELEGRAM_CHAT_ID" \
    --data parse_mode="Markdown" \
    --data-urlencode text="$message" >/dev/null 2>&1 || true
}

parse_auth_line() {
  local line="$1"

  if [[ "$line" =~ Accepted[[:space:]](publickey|password|keyboard-interactive.*)[[:space:]]for[[:space:]]([^[:space:]]+)[[:space:]]from[[:space:]]([^[:space:]]+) ]]; then
    local method="${BASH_REMATCH[1]}"
    local user="${BASH_REMATCH[2]}"
    local ip="${BASH_REMATCH[3]}"
    local msg="✅ SSH login succeeded:\nUser: *${user}*\nMethod: *${method}*\nIP: \\`${ip}\\`"
    send_telegram "$msg"
  fi
}

parse_fail2ban_line() {
  local line="$1"

  if [[ "$line" =~ Ban[[:space:]]([^[:space:]]+) ]]; then
    local ip="${BASH_REMATCH[1]}"
    local msg="🚫 fail2ban ban detected:\nIP: \\`${ip}\\`"
    send_telegram "$msg"
  fi
}

if [ ! -r "$AUTH_LOG" ]; then
  echo "[!] Cannot read auth log: $AUTH_LOG" >&2
  exit 1
fi

if [ ! -r "$FAIL2BAN_LOG" ]; then
  echo "[!] Cannot read fail2ban log: $FAIL2BAN_LOG" >&2
  exit 1
fi

trap 'echo "[+] Exiting..."; exit 0' INT TERM

echo "[+] Starting SSH monitor"

tail -Fn0 "$AUTH_LOG" "$FAIL2BAN_LOG" | while read -r line; do
  if [[ "$line" == *sshd*Accepted* ]]; then
    parse_auth_line "$line"
  elif [[ "$line" == *fail2ban*Ban* ]]; then
    parse_fail2ban_line "$line"
  fi
 done
