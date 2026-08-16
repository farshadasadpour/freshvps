# AGENTS.md

## What this repo is

A single-file bash script (`bootstrap-vps.sh`) that provisions a fresh Debian/Ubuntu VPS. There is no build, test, lint, CI, or application code — don't look for any. The README documents usage; the script is the source of truth.

## Key gotchas

- **Do not run this on your own dev machine.** It disables root login, disables password auth, and moves SSH to a non-standard port (default `2825`). It is meant for a fresh VPS only.
- **Must run as root** (checks `id -u`), with `set -euo pipefail` — it aborts hard on the first failure.
- **Behavior is set by env vars**, consumed at the top of the script:
  - `SSH_PUBKEY` (required unless running on a TTY; script exits otherwise)
  - `SSH_USER` (default `code`) — the sudo user created and the only allowed SSH user
  - `SSH_PORT` (default `2825`)
  - `ENABLE_FIREWALL` (default `0`) — UFW is NOT installed/configured unless set to `1`; ufw package is installed inside the guarded block
- Curl-pipe usage needs `sudo -E` so `SSH_PUBKEY` survives sudo, e.g. `SSH_PUBKEY="$(cat ~/.ssh/id_rsa.pub)" sudo -E bash bootstrap-vps.sh`.

## Consistency constraints inside the script

These values are hardcoded/written into multiple config files and must be kept consistent if changed:

- `$SSH_PORT` appears in `sshd_config.d/99-security.conf`, the UFW allow rule, and the fail2ban `jail.local` sshd section.
- `$SSH_USER` appears in `sudoers.d/$SSH_USER`, the `AllowUsers` line, and the `/home/$SSH_USER/.ssh` setup.

## Idempotency behavior

- Re-runs are safe-ish: oh-my-zsh install, swap creation, and `authorized_keys` append are guarded; ssh config, fail2ban, sysctl, and journald conf files are **overwritten** every run.
- `ufw --force reset` wipes any pre-existing firewall rules each run — but only when `ENABLE_FIREWALL=1`.

## oh-my-zsh install gotchas (non-root users)

The installer is run for root and for `$SSH_USER` (see `_install_ohmyzsh_for`). Both of these break it if "fixed" naively:

- `sudo -u user sh -c "install.sh"` inherits the parent's CWD (often `/root`, mode 700), and the installer's `cd -` then fails for the unprivileged user → `set -e` aborts the whole bootstrap. Must `cd "$HOME"` first.
- `sudo` strips exported `RUNZSH`/`CHSH`, so the installer defaults them to `yes` and launches an interactive `zsh`, hanging the script forever when stdin is a TTY (e.g. inside tmux). Must pass `RUNZSH=no CHSH=no` inside the `sudo` command and run with `< /dev/null`.
- Verify any change here against a real non-root install — a plain `bash -n` won't catch either failure mode.

## Verification

No test framework. Check syntax with `bash -n bootstrap-vps.sh`; run `shellcheck` if available. The script itself self-checks sshd config (`sshd -t`) and that ssh is listening on the new port before restarting.