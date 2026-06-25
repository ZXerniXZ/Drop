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
install -m 755 "$BACKEND_DIR/scripts/healthcheck.sh" "$BACKEND_DIR/scripts/healthcheck.sh"

# cloudflared: riavvio automatico se il processo termina
mkdir -p /etc/systemd/system/cloudflared.service.d
cat > /etc/systemd/system/cloudflared.service.d/restart.conf << 'EOF'
[Service]
Restart=always
RestartSec=10
EOF

systemctl daemon-reload
systemctl enable docker cloudflared drop-backend.service drop-healthcheck.timer
systemctl restart cloudflared || true
systemctl start drop-backend.service
systemctl start drop-healthcheck.timer

echo "OK — servizi Drop abilitati:"
systemctl is-enabled docker cloudflared drop-backend.service drop-healthcheck.timer
