#!/bin/bash

host='192.168.1.128'
porta='8022'
user='u0_a60'
pasta='~/storage/downloads/SHOW_PROXY_DECO'
# pasta='/data/data/com.termux/files/home/storage/downloads/SHOW_PROXY_DECO'

pass="$1"

# Verifica senha
if [[ -z "$pass" ]]; then
    echo -e "\e[1;31mUso: \e[1;37m$0 <password>\e[0m"
    exit 1
fi

# Verifica dependências
for cmd in sshpass rsync; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "\e[1;31m[ERRO]\e[0m Comando não encontrado: $cmd"
        exit 1
    fi
done

echo -e "\e[1;33mSincronizando arquivos de:\e[0m"
echo -e "  ${user}@${host}:${pasta}/"
echo -e "\e[1;33mPara:\e[0m"
echo -e "  $(pwd)"
echo

sshpass -p "$pass" rsync -avz \
    -e "ssh -p $porta" \
    "${user}@${host}:${pasta}/" \
    .

status=$?

if [[ $status -eq 0 ]]; then
    echo
    echo -e "\e[1;32m[OK] Transferência concluída com sucesso.\e[0m"
else
    echo
    echo -e "\e[1;31m[ERRO] Falha na transferência. Código: $status\e[0m"
    exit "$status"
fi



# Dar permissoes das pastas.
if [[ $EUID -eq 0 ]]; then
    USER="${SUDO_USER:-root}"
    chown -R "$USER:$USER" .
    chmod -R u+rwX .
else
    sudo chown -R "$USER:$USER" .
    sudo chmod -R u+rwX .
fi

