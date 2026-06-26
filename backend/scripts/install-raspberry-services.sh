#!/usr/bin/env bash
# Installa unit systemd Drop sulla Raspberry Pi (eseguire una volta con sudo).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND_DIR="$REPO_DIR/backend"
SYSTEMD_DIR="/etc/systemd/system"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Esegui con: sudo $0"
  exit 1
fi

install -m 644 "$BACKEND_DIR/systemd/drop-backend.service" "$SYSTEMD_DIR/drop-backend.service"
install -m 644 "$BACKEND_DIR/systemd/drop-healthcheck.service" "$SYSTEMD_DIR/drop-healthcheck.service"
install -m 644 "$BACKEND_DIR/systemd/drop-healthcheck.timer" "$SYSTEMD_DIR/drop-healthcheck.timer"
chmod 755 "$BACKEND_DIR/scripts/healthcheck.sh"

# cloudflared: riavvio automatico + HTTP/2 (più stabile per upload medi)
mkdir -p /etc/systemd/system/cloudflared.service.d
cat > /etc/systemd/system/cloudflared.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=10
EOF

if [[ -f /etc/systemd/system/cloudflared.service ]]; then
  if ! grep -q -- '--protocol http2' /etc/systemd/system/cloudflared.service; then
    sed -i 's|/usr/bin/cloudflared --no-autoupdate|/usr/bin/cloudflared --no-autoupdate --protocol http2|' \
      /etc/systemd/system/cloudflared.service
    echo "cloudflared: aggiunto --protocol http2"
  fi
fi

chmod 755 "$BACKEND_DIR/scripts/healthcheck.sh"
chmod 755 "$BACKEND_DIR/scripts/test_chunked_upload.sh"

systemctl daemon-reload
systemctl enable docker cloudflared drop-backend.service drop-healthcheck.timer
systemctl restart cloudflared || true
systemctl start drop-backend.service
systemctl start drop-healthcheck.timer

echo "OK — servizi Drop abilitati:"
systemctl is-enabled docker cloudflared drop-backend.service drop-healthcheck.timer
