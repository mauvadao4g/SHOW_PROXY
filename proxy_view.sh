#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_DIR="$DIR/captures"
mkdir -p "$CAPTURE_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOST_IP="$(hostname -I | awk '{print $1}')"

PORT=8080
FILTER=""
SAVE_FILE=""
REPLAY_FILE=""
MODE="dump"     # dump | tui | web
VERBOSE=0
DETAIL=""
EXPORT_TXT=""
EXPORT_HAR=""

usage() {
  cat <<EOF
Uso: $(basename "$0") [opções]

Captura ao vivo (escuta o proxy em 0.0.0.0:PORT):
  -p PORT         porta do proxy (default: 8080)
  -w FILE         salva a captura em FILE (default: captures/capture-<timestamp>.flow)
  -f FILTER       filtro de exibição, ex: -f "~d api.seuapp.com"
  -v              verbose: headers completos (mitmdump -v)
  -b              bem detalhado: headers + body (flow_detail=3)
  -t              interface TUI interativa (mitmproxy) em vez do stream
  -W              interface web (mitmweb) em vez do stream

Reabrindo/exportando captura já salva (não escuta proxy):
  -r FILE         reabre FILE (.flow) interativo (mitmproxy -r); combine com -W
                  pra abrir na web (mitmweb -r) em vez do TUI
  -x FILE         exporta FILE (.flow) pra texto legível (dump.txt) e sai
  --har FILE      exporta FILE (.flow) pra .har (formato JSON padrão) e sai

  -h              mostra esta ajuda

Exemplos:
  $(basename "$0")                                # ao vivo, stream simples
  $(basename "$0") -w captures/capture.flow        # ao vivo, salvando em arquivo fixo
  $(basename "$0") -f "~d api.seuapp.com"          # só requests desse domínio
  $(basename "$0") -v                              # headers completos
  $(basename "$0") -b                               # headers + body
  $(basename "$0") -t                               # TUI interativo ao vivo
  $(basename "$0") -r captures/capture.flow         # reabre salvo, interativo
  $(basename "$0") -r captures/capture.flow -W      # reabre salvo, na web
  $(basename "$0") -x captures/capture.flow         # exporta salvo pra dump.txt
  $(basename "$0") --har captures/capture.flow      # exporta salvo pra .har
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p) PORT="$2"; shift 2;;
    -w) SAVE_FILE="$2"; shift 2;;
    -f) FILTER="$2"; shift 2;;
    -v) VERBOSE=1; shift;;
    -b) DETAIL=3; shift;;
    -t) MODE="tui"; shift;;
    -W) MODE="web"; shift;;
    -r) REPLAY_FILE="$2"; shift 2;;
    -x) EXPORT_TXT="$2"; shift 2;;
    --har) EXPORT_HAR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Opção desconhecida: $1" >&2; usage; exit 1;;
  esac
done

# --- exportar .flow salvo para texto ---
if [ -n "$EXPORT_TXT" ]; then
  OUT="$CAPTURE_DIR/dump-$TIMESTAMP.txt"
  echo "Exportando '$EXPORT_TXT' -> '$OUT' (headers + body)..."
  # mitmdump -nr às vezes sai com código != 0 mesmo após escrever tudo certo; ignora.
  mitmdump -nr "$EXPORT_TXT" --set flow_detail=3 > "$OUT" || true
  echo "Pronto: $OUT"
  exit 0
fi

# --- exportar .flow salvo para .har ---
if [ -n "$EXPORT_HAR" ]; then
  OUT="${EXPORT_HAR%.flow}.har"
  echo "Exportando '$EXPORT_HAR' -> '$OUT'..."
  mitmdump -nr "$EXPORT_HAR" --set "hardump=$OUT" || true
  echo "Pronto: $OUT"
  exit 0
fi

# --- reabrir .flow salvo (interativo ou web) ---
if [ -n "$REPLAY_FILE" ]; then
  if [ "$MODE" = "web" ]; then
    echo "Reabrindo '$REPLAY_FILE' na interface web (http://localhost:8081)..."
    exec mitmweb --web-host 0.0.0.0 --web-port 8081 -r "$REPLAY_FILE"
  else
    exec mitmproxy -r "$REPLAY_FILE"
  fi
fi

# --- captura ao vivo ---
[ -z "$SAVE_FILE" ] && SAVE_FILE="$CAPTURE_DIR/capture-$TIMESTAMP.flow"
FLAGS=(--listen-host 0.0.0.0 --listen-port "$PORT" -w "$SAVE_FILE")
[ -n "$DETAIL" ] && FLAGS+=(--set "flow_detail=$DETAIL")
[ "$VERBOSE" = "1" ] && FLAGS+=(-v)
[ -n "$FILTER" ] && FLAGS+=("$FILTER")

echo "=================================================="
echo " Proxy (aponte o celular pra cá): $HOST_IP:$PORT"
echo " Salvando captura em: $SAVE_FILE"
[ -n "$FILTER" ] && echo " Filtro ativo: $FILTER"
echo " Certificado CA: acesse http://mitm.it PELO CELULAR (com o proxy já ativo)"
echo "=================================================="

case "$MODE" in
  tui) exec mitmproxy "${FLAGS[@]}";;
  web) exec mitmweb --web-host 0.0.0.0 --web-port 8081 "${FLAGS[@]}";;
  *)   exec mitmdump "${FLAGS[@]}";;
esac
