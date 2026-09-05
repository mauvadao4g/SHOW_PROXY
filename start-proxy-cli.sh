#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PORT="${PORT:-8080}"
FILTER="${FILTER:-}"       # ex: FILTER="api.seuapp.com" ./start-proxy-cli.sh
DETAIL="${DETAIL:-1}"      # 0=so' access log, 1=+headers, 2=+headers+body

ARGS=(-p "$PORT")
[ -n "$FILTER" ] && ARGS+=(-f "$FILTER")
case "$DETAIL" in
  2) ARGS+=(-b);;
  1) ARGS+=(-v);;
esac

# Atalho pra rodar em modo stream de texto com variaveis de ambiente em vez de flags.
exec bash "$DIR/proxy_view.sh" "${ARGS[@]}"
