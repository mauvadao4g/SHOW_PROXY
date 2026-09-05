#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8080}"
WEB_PORT="${WEB_PORT:-8081}"
CAPTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/captures"
mkdir -p "$CAPTURE_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FLOW_FILE="$CAPTURE_DIR/capture-$TIMESTAMP.flow"

HOST_IP="$(hostname -I | awk '{print $1}')"

echo "=================================================="
echo " mitmweb iniciando"
echo "  Proxy (aponte o celular pra cá): $HOST_IP:$PORT"
echo "  Interface web (abra no navegador): http://$HOST_IP:$WEB_PORT"
echo "  Gravando tráfego em: $FLOW_FILE"
echo "  Certificado CA: acesse http://mitm.it PELO CELULAR (com o proxy já ativo)"
echo "=================================================="

exec mitmweb \
  --listen-host 0.0.0.0 \
  --listen-port "$PORT" \
  --web-host 0.0.0.0 \
  --web-port "$WEB_PORT" \
  --save-stream-file "$FLOW_FILE"
