# PatchMaster Endpoint Agent v2 — Linux
## What's Inside This Package

| File | Purpose |
|---|---|
| `dist/endpoint-agent-v2-linux-amd64` | Agent binary (Linux x64, statically linked — no Go runtime needed) |
| `config.json` | Default configuration template |
| `deploy/install-linux.sh` | Automated installer (creates systemd service, runs as root) |

## Predefined Configuration Types Supported

| Config Type | What It Does | Linux Tool Used |
|---|---|---|
| `service_control` | Start / Stop / Enable / Disable systemd services | `systemctl` |
| `software_deployment` | Silent install of DEB / RPM packages or download+run | `dpkg` / `rpm` |
| `firewall_rule` | Add / remove firewall rules | `ufw` or `iptables` |
| `browser_policy` | Deploy Chrome and Firefox enterprise policy JSON | File write |
| `custom_script` | Run Bash scripts silently as root | `bash` |
| `registry_tweak` | ❌ Not applicable on Linux — skipped automatically | — |

## How to Install

### Step 1 — Set environment variables
```bash
export PATCHMASTER_API_URL='http://172.17.6.142:5000'
export PATCHMASTER_BOOTSTRAP_TOKEN='<your-temporary-secret>'
```

### Step 2 — Run installer as root
```bash
chmod +x ./deploy/install-linux.sh
sudo --preserve-env=PATCHMASTER_API_URL,PATCHMASTER_BOOTSTRAP_TOKEN ./deploy/install-linux.sh
```

### Step 3 — Verify
```bash
systemctl status endpoint-agent-v2 --no-pager
journalctl -u endpoint-agent-v2 -n 50 --no-pager
```

## What the Agent Does After Install

1. **Enrolls** itself with the API using the bootstrap token → receives unique endpoint token
2. **Scrubs** the bootstrap token from config.json (security)
3. **Heartbeat** every 60 seconds → API records last-seen timestamp
4. **Config Poll** every 30 seconds → picks up predefined configurations from dashboard
5. **Executes** each config task natively as root (silent)
6. **Reports** result (SUCCESS / FAILED + exit code) back to API
7. **Inventory** every 1 hour → sends hardware (CPU, RAM, Disk, Network) + installed packages (dpkg/rpm) to API

## Files Created on the Endpoint

| Path | Purpose |
|---|---|
| `/usr/local/bin/endpoint-agent-v2` | Agent executable |
| `/etc/endpoint-agent/config.json` | Runtime config (bootstrap token scrubbed after enroll) |
| `/var/lib/endpoint-agent/state.json` | Persists endpoint token + applied task IDs |
| `/var/log/endpoint-agent/agent.log` | Agent log file |
| `/var/cache/endpoint-agent/` | Temporary package download cache |
| `/etc/systemd/system/endpoint-agent-v2.service` | systemd service unit |

## Uninstall
```bash
sudo systemctl stop endpoint-agent-v2
sudo systemctl disable endpoint-agent-v2
sudo rm /etc/systemd/system/endpoint-agent-v2.service
sudo systemctl daemon-reload
sudo rm /usr/local/bin/endpoint-agent-v2
sudo rm -rf /etc/endpoint-agent /var/lib/endpoint-agent /var/log/endpoint-agent /var/cache/endpoint-agent
```

