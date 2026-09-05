#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PORT="${PORT:-8080}"

# Atalho pra subir direto no modo "web": mitmweb fora do Termux,
# dashboard de conexoes + certificado servido via HTTP dentro do Termux.
exec bash "$DIR/proxy_view.sh" -p "$PORT" -W
