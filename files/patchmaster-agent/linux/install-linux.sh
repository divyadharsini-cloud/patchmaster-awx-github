#!/bin/sh
set -eu
BIN=./dist/endpoint-agent-linux-amd64
[ -f "$BIN" ] || BIN=./endpoint-agent-linux-amd64
[ -f "$BIN" ] || { echo "endpoint-agent-linux-amd64 binary not found" >&2; exit 1; }
API=${PATCHMASTER_API_URL:-http://172.17.6.142:5000}
BOOTSTRAP=${PATCHMASTER_BOOTSTRAP_TOKEN:-}
[ -n "$BOOTSTRAP" ] || { echo "Set PATCHMASTER_BOOTSTRAP_TOKEN in the deployment environment" >&2; exit 1; }
case "$API" in https://*) ALLOW_HTTP=false ;; http://172.17.6.142:5000) ALLOW_HTTP=true ;; *) echo "Use http://172.17.6.142:5000 for this test or an HTTPS API URL" >&2; exit 1 ;; esac
install -d -m 0750 /etc/endpoint-agent /var/lib/endpoint-agent /var/log/endpoint-agent
install -m 0755 "$BIN" /usr/local/bin/endpoint-agent
if [ ! -f /etc/endpoint-agent/config.json ]; then install -m 0600 ./config.linux.example.json /etc/endpoint-agent/config.json; fi
python3 - "$API" "$BOOTSTRAP" "$ALLOW_HTTP" <<'PYCODE'
import json,sys
p='/etc/endpoint-agent/config.json'
with open(p, encoding='utf-8-sig') as f: d=json.load(f)
d['api_base_url']=sys.argv[1]
d['bootstrap_token']=sys.argv[2]
d['allow_insecure_http']=sys.argv[3].lower()=='true'
with open(p,'w') as f: json.dump(d,f,indent=2); f.write('\n')
PYCODE
chmod 0600 /etc/endpoint-agent/config.json
install -m 0644 ./deploy/endpoint-agent.service /etc/systemd/system/endpoint-agent.service
systemctl daemon-reload
systemctl enable --now endpoint-agent
systemctl --no-pager --full status endpoint-agent || true
