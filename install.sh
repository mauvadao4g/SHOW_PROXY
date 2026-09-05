#!/usr/bin/env bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERT_DIR="$DIR/certs"

echo "=================================================="
echo " Instalando dependencias do SHOW_PROXY"
echo "=================================================="

IS_TERMUX=0
if [ -n "$TERMUX_VERSION" ] || [ -d "/data/data/com.termux" ]; then
  IS_TERMUX=1
fi

if [ "$IS_TERMUX" = "1" ]; then
  echo "[ok] ambiente detectado: Termux (Android)"

  # 1. pacotes de sistema: python, pip, openssl (CLI) - via pkg/apt do Termux
  echo "[..] conferindo pacotes do Termux (python, python-pip, openssl-tool)..."
  pkg install -y python python-pip openssl-tool 2>&1 | tail -5

  if ! command -v openssl >/dev/null 2>&1; then
    echo "[erro] openssl (CLI) nao encontrado mesmo apos 'pkg install openssl-tool'." >&2
    echo "       Sem ele nao da pra gerar certificados. Rode manualmente:" >&2
    echo "         pkg install openssl-tool" >&2
    exit 1
  fi
  echo "[ok] openssl: $(openssl version)"

  # 2. proxy.py + certifi via pip --user (pura Python, sem compilar nada em Rust/C)
  echo "[..] instalando proxy.py e certifi via pip..."
  pip install --user --break-system-packages --upgrade proxy.py certifi 2>&1 | tail -15

  if ! python3 -c "import proxy" >/dev/null 2>&1; then
    echo "[erro] o modulo 'proxy' (proxy.py) nao ficou importavel. Verifique o output do pip acima." >&2
    exit 1
  fi
  echo "[ok] proxy.py: $(python3 -c 'from proxy.common.version import __version__; print(__version__)' 2>/dev/null || echo instalado)"

  # garante que ~/.local/bin (onde pip --user coloca scripts) esta no PATH
  LOCAL_BIN="$HOME/.local/bin"
  if [ -d "$LOCAL_BIN" ] && ! echo "$PATH" | tr ':' '\n' | grep -qx "$LOCAL_BIN"; then
    if ! grep -qs "$LOCAL_BIN" "$HOME/.bashrc" 2>/dev/null; then
      echo "export PATH=\"\$PATH:$LOCAL_BIN\"" >> "$HOME/.bashrc"
      echo "[ok] adicionado $LOCAL_BIN ao PATH em ~/.bashrc (abra um novo terminal pra valer)"
    fi
  fi
else
  # 1. python3
  if ! command -v python3 >/dev/null 2>&1; then
    echo "[erro] python3 nao encontrado. Instale antes de continuar (ex:  apt install python3)." >&2
  fi
  echo "[ok] python3: $(python3 --version)"

  # 2. pipx (usado pra instalar o mitmproxy isolado, sem sujar o python do sistema)
  if ! command -v pipx >/dev/null 2>&1; then
    echo "[..] pipx nao encontrado, instalando..."
    if command -v apt >/dev/null 2>&1; then
       apt update
       apt install -y pipx
    else
      python3 -m pip install --user pipx
    fi
    python3 -m pipx ensurepath
    echo "[ok] pipx instalado. Se os comandos 'mitmdump/mitmproxy/mitmweb' nao forem"
    echo "     encontrados depois, abra um novo terminal (o PATH foi atualizado)."
  else
    echo "[ok] pipx: $(pipx --version)"
  fi

  # 3. mitmproxy (fornece mitmdump, mitmproxy, mitmweb)
  if command -v mitmdump >/dev/null 2>&1; then
    echo "[ok] mitmproxy ja instalado: $(mitmdump --version 2>/dev/null | head -1)"
  else
    echo "[..] instalando mitmproxy via pipx..."
    pipx install mitmproxy
  fi
fi

# 4. permissoes, pasta de capturas e CA propria do proxy (usada em ambos os modos)
if chmod +x "$DIR"/*.sh 2>/dev/null; then
  echo "[ok] scripts marcados como executaveis"
else
  echo "[aviso] nao consegui dar chmod +x nos scripts (normal se o projeto estiver"
  echo "        em ~/storage/... - armazenamento compartilhado via FUSE nao suporta"
  echo "        bit de execucao). Rode os scripts com 'bash nome.sh' em vez de"
  echo "        './nome.sh', ou mova o projeto pra dentro de \$HOME (ex: ~/SHOW_PROXY)."
fi
mkdir -p "$DIR/captures"
mkdir -p "$CERT_DIR"
echo "[ok] pasta de capturas: $DIR/captures"

if [ "$IS_TERMUX" = "1" ]; then
  if [ ! -f "$CERT_DIR/ca-cert.pem" ] || [ ! -f "$CERT_DIR/ca-key.pem" ]; then
    echo "[..] gerando CA propria pra interceptacao HTTPS (uma vez so, fica salva em certs/)..."
    openssl genrsa -out "$CERT_DIR/ca-key.pem" 2048 2>/dev/null
    openssl req -new -x509 -days 3650 -key "$CERT_DIR/ca-key.pem" \
      -out "$CERT_DIR/ca-cert.pem" -subj "/CN=SHOW_PROXY Termux CA" 2>/dev/null
    cp "$CERT_DIR/ca-key.pem" "$CERT_DIR/ca-signing-key.pem"
    rm -rf "$CERT_DIR/generated"
    echo "[ok] CA gerada em $CERT_DIR/ca-cert.pem"
  else
    echo "[ok] CA ja existe em $CERT_DIR/ca-cert.pem (reaproveitada)"
  fi

  CA_SYSTEM_INSTALLED=0
  if command -v su >/dev/null 2>&1; then
    echo "[..] tentando instalar a CA como certificado de sistema (via root)..."
    if bash "$DIR/configure.sh" install-ca; then
      CA_SYSTEM_INSTALLED=1
    else
      echo "[aviso] nao foi possivel instalar como certificado de sistema automaticamente"
      echo "        (ver mensagem acima). Voce ainda pode instalar como certificado de"
      echo "        usuario (funciona pro navegador) - detalhes no README.md."
    fi
  else
    echo "[aviso] 'su' nao encontrado - pulei a instalacao automatica da CA como"
    echo "        certificado de sistema. Instale manualmente como certificado de"
    echo "        usuario (funciona pro navegador) - detalhes no README.md."
  fi
fi

HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$HOST_IP" ] && HOST_IP="$(ip -4 addr show scope global 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)"

echo "=================================================="
echo " Instalacao concluida!"
echo ""
echo " IP deste dispositivo na rede local: $HOST_IP"
echo ""
if [ "$IS_TERMUX" = "1" ]; then
  echo " Proximos passos:"
  echo "   1. bash proxy_view.sh"
  echo "      (configura e desfaz o proxy do sistema sozinho, se tiver root - senao,"
  echo "      configure manualmente: Wi-Fi > segure a rede > Modificar rede >"
  echo "      Opcoes avancadas > Proxy Manual > $HOST_IP:8080)"
  echo "   2. Certificado da CA:"
  if [ "$CA_SYSTEM_INSTALLED" = "1" ]; then
    echo "      - ja foi instalado como certificado de SISTEMA automaticamente acima."
    echo "        Se algum app ainda nao confiar, reinicie o aparelho."
  else
    echo "      - nao foi possivel instalar como certificado de sistema (ver aviso acima)."
    echo "      - baixe http://$HOST_IP:8080/ca-cert.pem pelo navegador do celular (com o"
    echo "        proxy ja ativo) e instale como certificado de usuario, OU"
    echo "      - rode 'bash configure.sh install-ca' de novo depois (ex: apos instalar"
    echo "        um modulo Magisk que libere a escrita em /system)"
  fi
else
  echo " Proximos passos:"
  echo "   1. ./proxy_view.sh"
  echo "   2. No celular, configure o proxy Wi-Fi manual para $HOST_IP:8080"
  echo "   3. No navegador do celular, acesse http://mitm.it e instale o certificado"
fi
echo ""
echo " Detalhes completos em README.md"
echo "=================================================="
