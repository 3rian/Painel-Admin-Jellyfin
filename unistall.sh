#!/bin/bash
set -e

BASE_DIR="/opt/jellyfin-expiry"
BIN_FILE="/usr/local/bin/jellyfin"

if [ "$(id -u)" -ne 0 ]; then
  echo "Execute como root."
  exit 1
fi

rm -f "$BIN_FILE"
rm -rf "$BASE_DIR"

crontab -l 2>/dev/null | grep -v "$BASE_DIR/jf-expiry.sh verificar" | crontab - || true

echo "Painel Jellyfin removido."
