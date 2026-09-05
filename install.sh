#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo " Instalando dependências do SHOW_PROXY"
echo "=================================================="

# 1. python3
if ! command -v python3 >/dev/null 2>&1; then
  echo "[erro] python3 não encontrado. Instale antes de continuar (ex: sudo apt install python3)." >&2
  exit 1
fi
echo "[ok] python3: $(python3 --version)"

# 2. pipx (usado pra instalar o mitmproxy isolado, sem sujar o python do sistema)
if ! command -v pipx >/dev/null 2>&1; then
  echo "[..] pipx não encontrado, instalando..."
  if command -v apt >/dev/null 2>&1; then
    sudo apt update
    sudo apt install -y pipx
  else
    python3 -m pip install --user pipx
  fi
  python3 -m pipx ensurepath
  echo "[ok] pipx instalado. Se os comandos 'mitmdump/mitmproxy/mitmweb' não forem"
  echo "     encontrados depois, abra um novo terminal (o PATH foi atualizado)."
else
  echo "[ok] pipx: $(pipx --version)"
fi

# 3. mitmproxy (fornece mitmdump, mitmproxy, mitmweb)
if command -v mitmdump >/dev/null 2>&1; then
  echo "[ok] mitmproxy já instalado: $(mitmdump --version 2>/dev/null | head -1)"
else
  echo "[..] instalando mitmproxy via pipx..."
  pipx install mitmproxy
fi

# 4. permissões e pasta de capturas
chmod +x "$DIR"/*.sh
mkdir -p "$DIR/captures"
echo "[ok] scripts marcados como executáveis"
echo "[ok] pasta de capturas: $DIR/captures"

HOST_IP="$(hostname -I | awk '{print $1}')"

echo "=================================================="
echo " Instalação concluída!"
echo ""
echo " IP deste computador na rede local: $HOST_IP"
echo ""
echo " Próximos passos:"
echo "   1. ./proxy_view.sh"
echo "   2. No celular, configure o proxy Wi-Fi manual para $HOST_IP:8080"
echo "   3. No navegador do celular, acesse http://mitm.it e instale o certificado"
echo ""
echo " Detalhes completos em README.md"
echo "=================================================="
