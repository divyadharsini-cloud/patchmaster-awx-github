#!/bin/sh
# PatchMaster Endpoint Agent v2.0.1 — Linux installer/upgrade
# Run as root. For a NEW endpoint only, provide PATCHMASTER_BOOTSTRAP_TOKEN.
# Existing enrolled endpoints retain /var/lib/endpoint-agent/state.json and do not
# need a bootstrap token during upgrades.
set -eu

BINARY="./dist/endpoint-agent-v2-linux-amd64"
CONFIG_DEST="/etc/endpoint-agent/config.json"
STATE_FILE="/var/lib/endpoint-agent/state.json"
SERVICE_FILE="/etc/systemd/system/endpoint-agent-v2.service"
SERVICE_NAME="endpoint-agent-v2"
DEFAULT_API="http://172.17.6.142:5000"

[ "$(id -u)" -eq 0 ] || { echo "ERROR: Run as root (sudo)." >&2; exit 1; }
[ -f "$BINARY" ] || { echo "ERROR: Binary not found at $BINARY" >&2; exit 1; }

install -d -m 0750 /etc/endpoint-agent /var/lib/endpoint-agent /var/log/endpoint-agent /var/cache/endpoint-agent

if [ ! -f "$CONFIG_DEST" ]; then
    [ -f ./config.json ] || { echo "ERROR: config.json not found." >&2; exit 1; }
    install -m 0600 ./config.json "$CONFIG_DEST"
fi

# Determine whether this endpoint already has a persistent enrollment token.
ENROLLED=false
if [ -s "$STATE_FILE" ] && command -v python3 >/dev/null 2>&1; then
    ENROLLED=$(python3 - "$STATE_FILE" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1], encoding='utf-8'))
    print('true' if d.get('endpoint_token') else 'false')
except Exception:
    print('false')
PY
)
fi

# API URL is preserved on upgrades unless explicitly overridden.
API_OVERRIDE="${PATCHMASTER_API_URL:-}"
BOOTSTRAP="${PATCHMASTER_BOOTSTRAP_TOKEN:-}"
if [ "$ENROLLED" != "true" ] && [ -z "$BOOTSTRAP" ]; then
    echo "ERROR: This endpoint has no saved enrollment token. Set PATCHMASTER_BOOTSTRAP_TOKEN for first enrollment." >&2
    exit 1
fi

# Stop before replacing the executable. The state/config are never removed.
if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo "Stopping existing $SERVICE_NAME service..."
    systemctl stop "$SERVICE_NAME"
fi

python3 - "$CONFIG_DEST" "$API_OVERRIDE" "$BOOTSTRAP" "$ENROLLED" <<'PY'
import json,sys,os,tempfile
p,api,bootstrap,enrolled=sys.argv[1:]
with open(p, encoding='utf-8-sig') as f: d=json.load(f)
if api: d['api_base_url']=api
if not enrolled and bootstrap: d['bootstrap_token']=bootstrap
if 'allow_insecure_http' not in d:
    d['allow_insecure_http']=str(d.get('api_base_url','')).startswith('http://')
fd,tmp=tempfile.mkstemp(prefix='.config-', dir=os.path.dirname(p), text=True)
try:
    with os.fdopen(fd,'w',encoding='utf-8') as f:
        json.dump(d,f,indent=2); f.write('\n')
    os.chmod(tmp,0o600); os.replace(tmp,p)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
chmod 0600 "$CONFIG_DEST"

# Atomic binary replacement.
install -m 0755 "$BINARY" /usr/local/bin/endpoint-agent-v2.new
mv -f /usr/local/bin/endpoint-agent-v2.new /usr/local/bin/endpoint-agent-v2

cat > "$SERVICE_FILE" <<'UNIT'
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
UNIT

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME" || systemctl start "$SERVICE_NAME"

echo ""
echo "PatchMaster Agent v2.0.1 installed/upgraded."
echo "Enrollment state preserved: $STATE_FILE"
echo "Verify: systemctl status $SERVICE_NAME --no-pager"
echo "Logs:   journalctl -u $SERVICE_NAME -f"
echo "Agent log: /var/log/endpoint-agent/agent.log"
