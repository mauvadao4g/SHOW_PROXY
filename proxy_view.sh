#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAPTURE_DIR="$DIR/captures"
CERT_DIR="$DIR/certs"
mkdir -p "$CAPTURE_DIR"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$HOST_IP" ] && HOST_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)"

IS_TERMUX=0
if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]; then
  IS_TERMUX=1
fi

PORT=8080
FILTER_DOMAIN=""
FILTER_METHOD=""
SAVE_FILE=""
REPLAY_FILE=""
MODE="dump"     # dump | tui | web
VERBOSE=0
DETAIL=0
NO_INTERCEPT=0
NO_AUTOCONFIG=0
EXPORT_TXT=""
EXPORT_HAR=""

usage() {
  cat <<EOF
Uso: $(basename "$0") [opcoes]

Captura ao vivo (escuta o proxy em 0.0.0.0:PORT):
  -p PORT         porta do proxy (default: 8080)
  -w FILE         salva a captura em FILE (default: captures/capture-<timestamp>.jsonl no
                  Termux, .flow no Linux)
  -f DOMINIO      so grava/mostra requests cujo host contenha DOMINIO (substring)
  -m METODO       so grava/mostra requests desse metodo HTTP (GET, POST, ...) [so Termux]
  -v              verbose: mostra headers ao vivo
  -b              bem detalhado: headers + body ao vivo
  -n              desativa interceptacao TLS (so repassa HTTPS, sem decifrar) [so Termux]
  -C              nao configura o proxy do sistema automaticamente (com root) [so Termux]
  -t              interface TUI interativa (mitmproxy) [so fora do Termux]
  -W              interface web: mitmweb fora do Termux; dashboard de conexoes no Termux

Reabrindo/exportando captura ja salva (nao escuta proxy):
  -r FILE         mostra o conteudo de FILE formatado no terminal
  -x FILE         exporta FILE pra texto legivel (captures/dump-<timestamp>.txt)
  --har FILE      exporta FILE pra .har (formato JSON padrao)

  -h              mostra esta ajuda

No Termux, o certificado da CA fica em certs/ca-cert.pem (gerado pelo install.sh) e e'
servido automaticamente em http://<ip>:PORT/ca-cert.pem enquanto o proxy estiver rodando.
Se tiver root, o proxy do SISTEMA (settings global http_proxy) e' configurado sozinho ao
subir e desfeito ao sair (Ctrl+C) - use -C pra desativar isso e configurar manualmente.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p) PORT="$2"; shift 2;;
    -w) SAVE_FILE="$2"; shift 2;;
    -f) FILTER_DOMAIN="$2"; shift 2;;
    -m) FILTER_METHOD="$2"; shift 2;;
    -v) VERBOSE=1; DETAIL=1; shift;;
    -b) DETAIL=2; shift;;
    -n) NO_INTERCEPT=1; shift;;
    -C) NO_AUTOCONFIG=1; shift;;
    -t) MODE="tui"; shift;;
    -W) MODE="web"; shift;;
    -r) REPLAY_FILE="$2"; shift 2;;
    -x) EXPORT_TXT="$2"; shift 2;;
    --har) EXPORT_HAR="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Opcao desconhecida: $1" >&2; usage; exit 1;;
  esac
done

# ---------------------------------------------------------------------------
# Modo Termux (proxy.py)
# ---------------------------------------------------------------------------
if [ "$IS_TERMUX" = "1" ]; then
  EXPORTER="$DIR/tools/export_capture.py"

  if [ -n "$EXPORT_TXT" ]; then
    OUT="$CAPTURE_DIR/dump-$TIMESTAMP.txt"
    python3 "$EXPORTER" "$EXPORT_TXT" --txt "$OUT"
    exit $?
  fi

  if [ -n "$EXPORT_HAR" ]; then
    OUT="${EXPORT_HAR%.jsonl}.har"
    python3 "$EXPORTER" "$EXPORT_HAR" --har "$OUT"
    exit $?
  fi

  if [ -n "$REPLAY_FILE" ]; then
    python3 "$EXPORTER" "$REPLAY_FILE" | less -R 2>/dev/null || python3 "$EXPORTER" "$REPLAY_FILE"
    exit $?
  fi

  [ -z "$SAVE_FILE" ] && SAVE_FILE="$CAPTURE_DIR/capture-$TIMESTAMP.jsonl"

  export PYTHONPATH="$DIR${PYTHONPATH:+:$PYTHONPATH}"
  FLAGS=(--hostname 0.0.0.0 --port "$PORT" --plugins plugins.capture_plugin.CapturePlugin)

  if [ "$NO_INTERCEPT" = "0" ]; then
    if [ ! -f "$CERT_DIR/ca-cert.pem" ]; then
      echo "[erro] certs/ca-cert.pem nao existe. Rode ./install.sh primeiro (ou use -n pra desativar a interceptacao)." >&2
      exit 1
    fi
    CAFILE="$(python3 -c 'import certifi; print(certifi.where())' 2>/dev/null)"
    if [ -z "$CAFILE" ]; then
      echo "[erro] modulo 'certifi' nao encontrado (pip install --user certifi). Rode ./install.sh." >&2
      exit 1
    fi
    mkdir -p "$CERT_DIR/generated"
    FLAGS+=(
      --ca-key-file "$CERT_DIR/ca-key.pem"
      --ca-cert-file "$CERT_DIR/ca-cert.pem"
      --ca-signing-key-file "$CERT_DIR/ca-signing-key.pem"
      --ca-cert-dir "$CERT_DIR/generated"
      --ca-file "$CAFILE"
      --enable-static-server --static-server-dir "$CERT_DIR"
    )
  fi

  [ "$MODE" = "web" ] && FLAGS+=(--enable-dashboard)
  if [ "$MODE" = "tui" ]; then
    echo "[aviso] -t (TUI interativa) nao existe no modo Termux/proxy.py; ignorando." >&2
  fi

  export CAPTURE_FILE="$SAVE_FILE"
  export CAPTURE_FILTER_DOMAIN="$FILTER_DOMAIN"
  export CAPTURE_FILTER_METHOD="$FILTER_METHOD"
  export CAPTURE_DETAIL="$DETAIL"

  echo "=================================================="
  echo " Proxy (aponte o celular pra ca): $HOST_IP:$PORT"
  echo " Salvando captura em: $SAVE_FILE"
  [ -n "$FILTER_DOMAIN" ] && echo " Filtro de dominio: $FILTER_DOMAIN"
  [ -n "$FILTER_METHOD" ] && echo " Filtro de metodo: $FILTER_METHOD"
  if [ "$NO_INTERCEPT" = "0" ]; then
    echo " Certificado CA: http://$HOST_IP:$PORT/ca-cert.pem (baixe PELO CELULAR com o proxy ja ativo)"
  else
    echo " Interceptacao TLS DESATIVADA (-n): HTTPS so' passa, sem decifrar"
  fi
  [ "$MODE" = "web" ] && echo " Dashboard: http://$HOST_IP:$PORT/dashboard"

  AUTOCONFIGURED=0
  if [ "$NO_AUTOCONFIG" = "0" ] && command -v su >/dev/null 2>&1 && su -c true 2>/dev/null; then
    if bash "$DIR/configure.sh" set "$PORT" >/dev/null 2>&1; then
      AUTOCONFIGURED=1
      echo " Proxy do sistema configurado automaticamente (sera desfeito ao sair)"
      trap 'bash "$DIR/configure.sh" unset >/dev/null 2>&1' EXIT INT TERM
    fi
  fi
  [ "$AUTOCONFIGURED" = "0" ] && echo " Configure o proxy manualmente: Wi-Fi > Modificar rede > Proxy Manual > $HOST_IP:$PORT"
  echo "=================================================="

  python3 -m proxy "${FLAGS[@]}"
  exit $?
fi

# ---------------------------------------------------------------------------
# Modo Linux (mitmproxy) - comportamento original do projeto
# ---------------------------------------------------------------------------
FILTER="$FILTER_DOMAIN"

if [ -n "$EXPORT_TXT" ]; then
  OUT="$CAPTURE_DIR/dump-$TIMESTAMP.txt"
  echo "Exportando '$EXPORT_TXT' -> '$OUT' (headers + body)..."
  mitmdump -nr "$EXPORT_TXT" --set flow_detail=3 > "$OUT" || true
  echo "Pronto: $OUT"
  exit 0
fi

if [ -n "$EXPORT_HAR" ]; then
  OUT="${EXPORT_HAR%.flow}.har"
  echo "Exportando '$EXPORT_HAR' -> '$OUT'..."
  mitmdump -nr "$EXPORT_HAR" --set "hardump=$OUT" || true
  echo "Pronto: $OUT"
  exit 0
fi

if [ -n "$REPLAY_FILE" ]; then
  if [ "$MODE" = "web" ]; then
    echo "Reabrindo '$REPLAY_FILE' na interface web (http://localhost:8081)..."
    exec mitmweb --web-host 0.0.0.0 --web-port 8081 -r "$REPLAY_FILE"
  else
    exec mitmproxy -r "$REPLAY_FILE"
  fi
fi

[ -z "$SAVE_FILE" ] && SAVE_FILE="$CAPTURE_DIR/capture-$TIMESTAMP.flow"
FLAGS=(--listen-host 0.0.0.0 --listen-port "$PORT" -w "$SAVE_FILE")
[ "$DETAIL" != "0" ] && FLAGS+=(--set "flow_detail=$DETAIL")
[ "$VERBOSE" = "1" ] && FLAGS+=(-v)
[ -n "$FILTER" ] && FLAGS+=("$FILTER")

echo "=================================================="
echo " Proxy (aponte o celular pra ca): $HOST_IP:$PORT"
echo " Salvando captura em: $SAVE_FILE"
[ -n "$FILTER" ] && echo " Filtro ativo: $FILTER"
echo " Certificado CA: acesse http://mitm.it PELO CELULAR (com o proxy ja ativo)"
echo "=================================================="

case "$MODE" in
  tui) exec mitmproxy "${FLAGS[@]}";;
  web) exec mitmweb --web-host 0.0.0.0 --web-port 8081 "${FLAGS[@]}";;
  *)   exec mitmdump "${FLAGS[@]}";;
esac
