#!/bin/sh
# PatchMaster Endpoint Agent v2 — Linux Installer
# Run as root. Set env variables before running:
#   export PATCHMASTER_API_URL='http://172.17.6.142:5000'
#   export PATCHMASTER_BOOTSTRAP_TOKEN='<your-secret>'
#   sudo --preserve-env=PATCHMASTER_API_URL,PATCHMASTER_BOOTSTRAP_TOKEN ./install-linux.sh

set -eu

BINARY="./dist/endpoint-agent-v2-linux-amd64"
CONFIG_DEST="/etc/endpoint-agent/config.json"
SERVICE_FILE="/etc/systemd/system/endpoint-agent-v2.service"
SERVICE_NAME="endpoint-agent-v2"

API="${PATCHMASTER_API_URL:-http://172.17.6.142:5000}"
BOOTSTRAP="${PATCHMASTER_BOOTSTRAP_TOKEN:-}"

# ── Validate ──────────────────────────────────────────────────────────────────
[ -f "$BINARY" ] || { echo "ERROR: Binary not found at $BINARY" >&2; exit 1; }
[ -n "$BOOTSTRAP" ] || { echo "ERROR: Set PATCHMASTER_BOOTSTRAP_TOKEN" >&2; exit 1; }

echo "=== PatchMaster Agent v2 — Linux Installer ==="
echo "API URL : $API"
echo "Binary  : $BINARY"

# ── Determine allow_insecure_http ────────────────────────────────────────────
case "$API" in
    https://*) ALLOW_HTTP=false ;;
    *)         ALLOW_HTTP=true  ;;
esac

# ── Create directories ────────────────────────────────────────────────────────
echo "Creating directories..."
install -d -m 0750 /etc/endpoint-agent
install -d -m 0750 /var/lib/endpoint-agent
install -d -m 0750 /var/log/endpoint-agent
install -d -m 0750 /var/cache/endpoint-agent

# ── Install binary ────────────────────────────────────────────────────────────
echo "Installing binary -> /usr/local/bin/endpoint-agent-v2"
install -m 0755 "$BINARY" /usr/local/bin/endpoint-agent-v2

# ── Write config (only if not already present) ───────────────────────────────
if [ ! -f "$CONFIG_DEST" ]; then
    echo "Writing config.json..."
    install -m 0600 ./config.json "$CONFIG_DEST"
fi

# ── Inject runtime values into config.json via python3 ───────────────────────
echo "Updating config.json with API URL and bootstrap token..."
python3 - "$API" "$BOOTSTRAP" "$ALLOW_HTTP" <<'PYCODE'
import json, sys
p = '/etc/endpoint-agent/config.json'
with open(p, encoding='utf-8-sig') as f:
    d = json.load(f)
d['api_base_url']        = sys.argv[1]
d['bootstrap_token']     = sys.argv[2]
d['allow_insecure_http'] = sys.argv[3].lower() == 'true'
with open(p, 'w') as f:
    json.dump(d, f, indent=2)
    f.write('\n')
PYCODE
chmod 0600 "$CONFIG_DEST"

# ── Write systemd service unit ────────────────────────────────────────────────
echo "Writing systemd service unit..."
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=PatchMaster Endpoint Agent v2
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/endpoint-agent-v2 -config /etc/endpoint-agent/config.json
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
WorkingDirectory=/var/lib/endpoint-agent

[Install]
WantedBy=multi-user.target
EOF

# ── Enable and start ──────────────────────────────────────────────────────────
echo "Enabling and starting service..."
systemctl daemon-reload
systemctl enable --now "$SERVICE_NAME"

echo ""
echo "=== Installation complete! ==="
echo "Verify:"
echo "  systemctl status $SERVICE_NAME --no-pager"
echo "  journalctl -u $SERVICE_NAME -n 50 --no-pager"
echo ""
echo "Capabilities:"
echo "  Heartbeat   : Every 60 seconds  -> /api/v1/agents/checkin"
echo "  Config Poll : Every 30 seconds  -> /api/v1/agents/config"
echo "  Inventory   : Every 1 hour      -> /api/v1/agents/inventory"
echo "  Config Types: service_control, software_deployment,"
echo "                firewall_rule (ufw/iptables), browser_policy, custom_script"
echo "  Note        : registry_tweak is Windows-only (skipped on Linux)"

