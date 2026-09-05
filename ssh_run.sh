#!/bin/bash

PASS="$1"
[[ -z "$1" ]] && {
echo "Digite o password"
echo "$0 <password>"
exit 0
}

# Conectando via ssh
SSH="sshpass -p"${PASS}" ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o PubkeyAuthentication=no -p 8022 u0_a60@192.168.1.128"
     eval $SSH "'cd ~/storage/downloads/SHOW_PROXY && setsid bash proxy_view.sh -b > proxy_run.log 2>&1 < /dev/null & echo \"started, pgid: \$!\"'"



