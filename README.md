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
- configures UFW firewall (optional, opt-in via `ENABLE_FIREWALL=1`)
- enables Fail2Ban and auditd
- enables unattended upgrades
- adds 2 GB swap
- applies sysctl and journald tuning
- installs `certbot` (Let's Encrypt) and enables its auto-renewal timer

## SSL Certificates

The script installs `certbot` (Let's Encrypt) and `openssl` is available for self-signed certs. Choose the option that fits.

### Option 1: Let's Encrypt (requires a domain)

Point a domain (or subdomain) at this VPS first, then request a cert:

```bash
sudo certbot certonly --standalone -d panel.example.com --agree-tos -m you@example.com
```

Cert files land in `/etc/letsencrypt/live/panel.example.com/`:
- `fullchain.pem` — cert + chain (use in web servers)
- `privkey.pem` — private key (keep private)
- `cert.pem` / `chain.pem` — cert and chain separately

Renewal is automatic — the bootstrap script enabled the `certbot-renew.timer`. Test it with:

```bash
sudo certbot renew --dry-run
```

> Note: `--standalone` needs ports 80/443 free while issuing. If a web server is already running, use its plugin instead, e.g. `sudo certbot --nginx -d panel.example.com`.

### Option 2: Self-signed (no domain needed)

```bash
sudo openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 365 \
  -keyout /etc/ssl/private/panel.key \
  -out /etc/ssl/certs/panel.crt \
  -subj "/CN=<your-server-ip>"
```

Use `panel.crt` as the certificate and `panel.key` as the key. Browsers will warn about the untrusted issuer — add the cert to your device trust store to silence it.

### Example: serve a panel over HTTPS with nginx

Works for any local HTTP service (e.g. the 3x-ui panel on port 23920):

```bash
sudo apt install -y nginx

sudo tee /etc/nginx/sites-available/x-ui >/dev/null <<'EOF'
server {
    listen 443 ssl;
    server_name panel.example.com;

    ssl_certificate     /etc/letsencrypt/live/panel.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/panel.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:23920;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/x-ui /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

For a self-signed cert, replace the two `ssl_certificate*` lines with your `.crt`/`.key` paths. Keep the upstream panel bound to localhost so it is only reachable through nginx over HTTPS.
