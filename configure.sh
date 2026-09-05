#!/usr/bin/env bash
# Automacoes de root pro SHOW_PROXY no Termux/Android:
#   - configurar/desfazer o proxy do SISTEMA (Wi-Fi, Ethernet/USB, qualquer rede)
#   - instalar a CA do projeto como certificado de sistema (pra HTTPS de apps de terceiros)
#
# Uso:
#   bash configure.sh set [porta]     # aponta o proxy do sistema pra este dispositivo:porta (default 8080)
#   bash configure.sh set IP:PORTA    # aponta pra outro host (proxy rodando em outro lugar da rede)
#   bash configure.sh unset           # restaura o proxy do sistema pro que estava antes de rodar 'set'
#   bash configure.sh status          # mostra o valor atual (settings global http_proxy)
#   bash configure.sh install-ca      # instala certs/ca-cert.pem como CA de sistema (nao interativo)
#
# Tudo aqui precisa de root (su). 'set'/'unset'/'status' usam 'settings put/get global',
# que costuma funcionar mesmo em root "restrito" (sandboxed) que bloqueia escrita em
# /system. 'install-ca' precisa remontar /system como gravavel - se o root for restrito
# de verdade, essa parte falha e o script explica as alternativas, sem quebrar nada.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$DIR/.proxy_state"

ACTION="${1:-status}"
ARG="${2:-8080}"

if ! command -v su >/dev/null 2>&1; then
  echo "[erro] comando 'su' nao encontrado. Sem root nao da pra configurar o proxy do sistema automaticamente." >&2
  echo "       Alternativa manual: Wi-Fi > segure a rede > Modificar rede > Opcoes avancadas > Proxy: Manual" >&2
  exit 1
fi

get_current() {
  su -c "settings get global http_proxy" 2>/dev/null | tr -d '\r'
}

set_proxy() {
  local value="$1"
  su -c "settings put global http_proxy '$value'" 2>&1
}

case "$ACTION" in
  set)
    HOST_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)"
    [ -z "$HOST_IP" ] && HOST_IP="127.0.0.1"

    if [[ "$ARG" == *:* ]]; then
      TARGET="$ARG"
    else
      TARGET="$HOST_IP:$ARG"
    fi

    CURRENT="$(get_current)"
    if [ "$CURRENT" != "null" ] && [ -n "$CURRENT" ] && [ ! -f "$STATE_FILE" ]; then
      echo "$CURRENT" > "$STATE_FILE"
    elif [ ! -f "$STATE_FILE" ]; then
      echo ":0" > "$STATE_FILE"
    fi

    OUT="$(set_proxy "$TARGET")"
    if [ -n "$OUT" ]; then
      echo "[erro] falha ao configurar o proxy do sistema:" >&2
      echo "$OUT" >&2
      echo "" >&2
      echo "       Isso significa que seu 'su' nao esta liberando essa chamada." >&2
      echo "       Alternativa manual: Wi-Fi > segure a rede > Modificar rede >" >&2
      echo "       Opcoes avancadas > Proxy: Manual > Hostname: $HOST_IP, Porta: ${TARGET##*:}" >&2
      exit 1
    fi

    NEW="$(get_current)"
    echo "[ok] proxy do sistema configurado: $NEW"
    echo "     (era '$(cat "$STATE_FILE")' antes - rode 'bash configure.sh unset' pra desfazer)"
    ;;

  unset)
    if [ ! -f "$STATE_FILE" ]; then
      echo "[aviso] nao ha' estado salvo (nunca rodou 'set' por aqui). Limpando pra ':0' (sem proxy)."
      PREVIOUS=":0"
    else
      PREVIOUS="$(cat "$STATE_FILE")"
    fi

    OUT="$(set_proxy "$PREVIOUS")"
    if [ -n "$OUT" ]; then
      echo "[erro] falha ao restaurar o proxy do sistema:" >&2
      echo "$OUT" >&2
      exit 1
    fi

    rm -f "$STATE_FILE"
    echo "[ok] proxy do sistema restaurado pra: $(get_current)"
    ;;

  status)
    CURRENT="$(get_current)"
    echo "Proxy do sistema (settings global http_proxy): ${CURRENT:-<vazio/erro>}"
    if [ -f "$STATE_FILE" ]; then
      echo "Valor salvo antes do ultimo 'set' (usado por 'unset'): $(cat "$STATE_FILE")"
    fi
    ;;

  install-ca)
    CERT="$DIR/certs/ca-cert.pem"
    if [ ! -f "$CERT" ]; then
      echo "[erro] $CERT nao existe. Rode ./install.sh primeiro." >&2
      exit 1
    fi
    if ! command -v openssl >/dev/null 2>&1; then
      echo "[erro] openssl (CLI) nao encontrado. Rode: pkg install openssl-tool" >&2
      exit 1
    fi

    HASH="$(openssl x509 -inform PEM -subject_hash_old -in "$CERT" -noout 2>/dev/null | head -1)"
    if [ -z "$HASH" ]; then
      echo "[erro] nao consegui calcular o hash do certificado." >&2
      exit 1
    fi
    DEST="/system/etc/security/cacerts/${HASH}.0"
    LOCAL_CONTENT="$(cat "$CERT")"

    ALREADY="$(su -c "cat '$DEST'" 2>/dev/null)"
    if [ "$ALREADY" = "$LOCAL_CONTENT" ]; then
      echo "[ok] certificado ja instalado como CA de sistema em $DEST"
      exit 0
    fi

    su -c "mount -o rw,remount /system" >/dev/null 2>&1
    COPY_ERR="$(su -c "cp '$CERT' '$DEST' && chmod 644 '$DEST'" 2>&1 >/dev/null)"
    VERIFY="$(su -c "cat '$DEST'" 2>/dev/null)"
    su -c "mount -o ro,remount /system" >/dev/null 2>&1

    if [ "$VERIFY" = "$LOCAL_CONTENT" ]; then
      echo "[ok] certificado instalado como CA de sistema em $DEST."
      echo "     Reinicie o aparelho pra garantir que todos os apps peguem a mudanca."
      exit 0
    fi

    echo "[aviso] nao deu pra instalar o certificado como CA de sistema (root restrito" >&2
    echo "        nesse aparelho pra gravar em /system)." >&2
    [ -n "$COPY_ERR" ] && echo "$COPY_ERR" >&2
    echo "" >&2
    echo "        Alternativas: modulo Magisk 'Always Trust User Certificates', instalar" >&2
    echo "        $CERT como certificado de USUARIO, ou network_security_config.xml" >&2
    echo "        (se o APK for seu). Detalhes no README.md." >&2
    exit 1
    ;;

  *)
    echo "Uso: $(basename "$0") set [porta|IP:PORTA] | unset | status | install-ca" >&2
    exit 1
    ;;
esac
