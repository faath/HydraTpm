#!/bin/bash
set -e

#################################
# CONFIGURAÇÕES
#################################
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"

exec > >(tee -a "$LOG") 2>&1

#################################
# IDENTIFICAÇÃO (LIVE MODE)
#################################
echo ""
read -rp "👤 Nick do Discord (ex: Breno#1234): " DISCORD_NICK

if [[ -z "$DISCORD_NICK" ]]; then
    echo "❌ Nick do Discord é obrigatório."
    exit 1
fi

# Normalização segura
DISCORD_NICK_CLEAN="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:]#._-' | cut -c1-32)"

HOSTNAME="$(hostname)"
LIVE_USER="$(whoami)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%Y-%m-%d %H:%M:%S')"

# ID único da execução
EXEC_ID="$(echo "$DISCORD_NICK_CLEAN-$HOSTNAME-$EXEC_TIME" | sha256sum | awk '{print $1}')"

#################################
# INÍCIO DA EXECUÇÃO
#################################
echo "🚀 Iniciando execução TPM"
echo "👤 Discord: $DISCORD_NICK_CLEAN"
echo "🕒 Execução: $EXEC_TIME"
echo "🆔 ExecID: ${EXEC_ID:0:12}"

export DEBIAN_FRONTEND=noninteractive

echo "📦 Atualizando sistema..."
apt update && apt upgrade -y

echo "📦 Instalando tpm2-tools..."
apt install -y tpm2-tools

#################################
# PROCESSO TPM
#################################
if [ ! -e /dev/tpm0 ]; then
    STATUS="❌ FALHA"
    ERROR_MSG="TPM não encontrado"
else
    echo "🔐 Limpando TPM..."
    tpm2_clear || true

    echo "🔑 Criando primário SHA-256..."
    tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx

    echo "📄 Exportando chave pública..."
    tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem

    echo "🔑 Criando primário SHA-1..."
    tpm2_createprimary -C e -g sha1 -G rsa -c primary.ctx || true

    echo "⚠️ Tentando MD5 (esperado falhar)..."
    tpm2_createprimary -C e -g md5 -G rsa -c primary.ctx || true

    echo "📌 Fixando chave no TPM..."
    tpm2_evictcontrol -C o -c primary.ctx 0x81010001 || true

    STATUS="✅ SUCESSO"
    ERROR_MSG="Nenhum"
fi

#################################
# GERAÇÃO DE CÓDIGOS (HASHES)
#################################
HASH_SOURCE="${DISCORD_NICK_CLEAN}|${HOSTNAME}|${EXEC_TIME}|${STATUS}"

MD5_HASH="$(echo -n "$HASH_SOURCE" | md5sum | awk '{print $1}')"
SHA1_HASH="$(echo -n "$HASH_SOURCE" | sha1sum | awk '{print $1}')"
SHA256_HASH="$(echo -n "$HASH_SOURCE" | sha256sum | awk '{print $1}')"

# Salva também no log
{
  echo ""
  echo "🔐 CÓDIGOS GERADOS"
  echo "MD5:    $MD5_HASH"
  echo "SHA1:   $SHA1_HASH"
  echo "SHA256: $SHA256_HASH"
} >> "$LOG"

#################################
# RESUMO LIMPO PARA O DISCORD
#################################
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

🔐 **Códigos Gerados**
\`\`\`
MD5:     ${MD5_HASH}
SHA1:    ${SHA1_HASH}
SHA256:  ${SHA256_HASH}
\`\`\`

📎 Log completo anexado
━━━━━━━━━━━━━━━━━━"

#################################
# ENVIO PARA O DISCORD
#################################
echo "📡 Enviando relatório para o Discord..."

curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "{\"content\":\"$SUMMARY\"}"

curl -s -X POST "$WEBHOOK_URL" \
  -F "file=@$LOG"

#################################
# FINALIZAÇÃO
#################################
echo "🔁 Reiniciando máquina em 10 segundos..."
sleep 10

