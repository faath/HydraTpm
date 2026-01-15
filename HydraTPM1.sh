#!/bin/bash
set -e

WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"

exec > >(tee -a "$LOG") 2>&1

echo ""
read -rp "👤 Nick do Discord (ex: Marinho#1234): " DISCORD_NICK

if [[ -z "$DISCORD_NICK" ]]; then
    echo "❌ Nick do Discord é obrigatório."
    exit 1
fi

DISCORD_NICK_CLEAN="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:]#._-' | cut -c1-32)"

HOSTNAME="$(hostname)"
LIVE_USER="$(whoami)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

EXEC_ID="$(echo "$DISCORD_NICK_CLEAN-$HOSTNAME-$EXEC_TIME" | sha256sum | awk '{print $1}')"

echo "🚀 Iniciando execução TPM"
echo "👤 Discord: $DISCORD_NICK_CLEAN"
echo "🕒 Data: $EXEC_TIME"
echo "🆔 ExecID: ${EXEC_ID:0:12}"

export DEBIAN_FRONTEND=noninteractive

apt update && apt upgrade -y
apt install -y tpm2-tools

if [ ! -e /dev/tpm0 ]; then
    STATUS="❌ FALHA"
    ERROR_MSG="TPM não encontrado"
else
    tpm2_clear || true
    tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx
    tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem
    tpm2_createprimary -C e -g sha1 -G rsa -c primary.ctx || true
    tpm2_createprimary -C e -g md5 -G rsa -c primary.ctx || true
    tpm2_evictcontrol -C o -c primary.ctx 0x81010001 || true
    STATUS="✅ SUCESSO"
    ERROR_MSG="Nenhum"
fi

SUMMARY="🧾 **HYDRA TPM – RELATÓRIO**
━━━━━━━━━━━━━━━━━━
👤 Discord: \`${DISCORD_NICK_CLEAN}\`
👥 Usuário Live: \`${LIVE_USER}\`
💻 Host: \`${HOSTNAME}\`
🌐 IP: \`${IP_ADDR}\`
🕒 Execução: \`${EXEC_TIME}\`
🆔 ExecID: \`${EXEC_ID:0:16}\`

📌 Status: **${STATUS}**
⚠️ Erro: \`${ERROR_MSG}\`

📎 Log completo anexado
━━━━━━━━━━━━━━━━━━"


echo "📡 Enviando relatório para o Discord..."

curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"$SUMMARY\"}"

curl -s -X POST "$WEBHOOK_URL" \
  -F "file=@$LOG"


echo "🔁 Reiniciando máquina em 10 segundos..."
sleep 10

