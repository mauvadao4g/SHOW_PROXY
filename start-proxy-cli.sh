#!/usr/bin/env bash
set -euo pipefail

PORT="${PORT:-8080}"
FILTER="${FILTER:-}"       # ex: FILTER="~d api.seuapp.com" ./start-proxy-cli.sh
DETAIL="${DETAIL:-2}"      # 0=quieto 1=curto 2=headers 3=headers+body
CAPTURE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/captures"
mkdir -p "$CAPTURE_DIR"

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
FLOW_FILE="$CAPTURE_DIR/capture-$TIMESTAMP.flow"
LOG_FILE="$CAPTURE_DIR/capture-$TIMESTAMP.log"

HOST_IP="$(hostname -I | awk '{print $1}')"

echo "=================================================="
echo " mitmdump iniciando"
echo "  Proxy (aponte o celular pra cá): $HOST_IP:$PORT"
echo "  Gravando .flow (reabrir com 'mitmproxy -r'): $FLOW_FILE"
echo "  Log de texto (headers+body): $LOG_FILE"
if [ -n "$FILTER" ]; then echo "  Filtro ativo: $FILTER"; fi
echo "  Certificado CA: acesse http://mitm.it PELO CELULAR (com o proxy já ativo)"
echo "=================================================="

CMD=(mitmdump
  --listen-host 0.0.0.0
  --listen-port "$PORT"
  --set "flow_detail=$DETAIL"
  -w "$FLOW_FILE"
)

if [ -n "$FILTER" ]; then
  CMD+=("$FILTER")
fi

"${CMD[@]}" | tee "$LOG_FILE"
