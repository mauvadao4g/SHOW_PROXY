#!/usr/bin/env bash
# Para um proxy_view.sh rodando em background (ex: iniciado com setsid/nohup).
#
# Precisa mandar o sinal pro GRUPO inteiro do processo, nao so pro PID do bash -
# senao o processo python3 do proxy fica orfao rodando e o trap de limpeza
# (configure.sh unset) nunca dispara. Um Ctrl+C normal num terminal interativo ja
# faz isso sozinho; esse script existe pra quando o proxy foi iniciado desacoplado
# de um terminal (background/SSH sem tty).

set -uo pipefail

PID=""
for CANDIDATE in $(pgrep -f 'bash proxy_view.sh'); do
  PGID="$(ps -o pgid= -p "$CANDIDATE" 2>/dev/null | tr -d ' ')"
  if [ "$PGID" = "$CANDIDATE" ]; then
    PID="$CANDIDATE"
    break
  fi
done

if [ -z "$PID" ]; then
  echo "Nenhum proxy_view.sh rodando (nada pra parar)."
  exit 0
fi

echo "Parando proxy_view.sh (pid $PID, grupo -$PID)..."
kill -INT -"$PID"

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Parado. Proxy do sistema restaurado (via trap do proxy_view.sh)."
    exit 0
  fi
  sleep 1
done

echo "[aviso] ainda rodando apos 10s, forcando com SIGKILL no grupo..." >&2
kill -9 -"$PID" 2>/dev/null
echo "[aviso] como foi SIGKILL, o trap de limpeza pode nao ter rodado - confira com:" >&2
echo "        bash configure.sh status" >&2
