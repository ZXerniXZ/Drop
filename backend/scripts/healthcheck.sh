#!/usr/bin/env bash
# Verifica backend locale e tunnel; riavvia se necessario dopo reboot o caduta Wi-Fi.
set -euo pipefail

DROP_DIR="${DROP_DIR:-/home/ares/Drop/backend}"
BACKEND_PORT=8083

if [[ -f "$DROP_DIR/.env" ]]; then
  val=$(grep -E '^BACKEND_PORT=' "$DROP_DIR/.env" | cut -d= -f2- | tr -d '[:space:]')
  [[ -n "$val" ]] && BACKEND_PORT="$val"
fi

if ! curl -sf --max-time 10 "http://localhost:${BACKEND_PORT}/docs" >/dev/null; then
  echo "$(date -Is) backend down — restarting compose"
  sudo -u ares bash -c "cd '$DROP_DIR' && docker compose up -d --remove-orphans"
fi

if ! systemctl is-active --quiet cloudflared; then
  echo "$(date -Is) cloudflared down — starting service"
  systemctl start cloudflared
fi
