#!/bin/bash
set -e

################################
# CONFIGURAÇÕES
################################
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/SEU_WEBHOOK_AQUI"
WORKDIR="/tmp/hydra-tpm"
PUBKEY="$WORKDIR/endorsement_pub.pem"
CTX="$WORKDIR/primary.ctx"

mkdir -p "$WORKDIR"
cd "$WORKDIR"

################################
# IDENTIFICAÇÃO DO USUÁRIO
################################
read -rp "👤 Nick do Discord (ex: Marinho#1234): " DISCORD_NICK

EXEC_DATE=$(date "+%Y-%m-%d %H:%M:%S")
EXEC_ID=$(hostname | sha1sum | cut -c1-12)

################################
# GARANTIR ROOT
################################
if [ "$EUID" -ne 0 ]; then
  echo "❌ Execute como root"
  exit 1
fi

################################
# SISTEMA (SILENCIOSO)
################################
export DEBIAN_FRONTEND=noninteractive

apt update -y   >/dev/null 2>&1 || true
apt upgrade -y  >/dev/null 2>&1 || true
apt install -y tpm2-tools >/dev/null 2>&1

################################
# TPM CHECK
################################
if [ ! -e /dev/tpm0 ]; then
  curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"❌ **HYDRA TPM**\\n👤 **$DISCORD_NICK**\\nTPM não detectado.\"}"
  exit 1
fi

################################
# COMANDOS TPM (EXATOS)
################################
tpm2_clear >/dev/null 2>&1 || true

# SHA256
tpm2_createprimary -C e -g sha256 -G rsa -c "$CTX" >/dev/null 2>&1

# Exportar chave pública
tpm2_readpublic -c "$CTX" -f pem -o "$PUBKEY" >/dev/null 2>&1

# SHA1
tpm2_createprimary -C e -g sha1 -G rsa -c "$CTX" >/dev/null 2>&1 || true

# MD5 (esperado falhar)
tpm2_createprimary -C e -g md5 -G rsa -c "$CTX" >/dev/null 2>&1 || true

# Persistência
tpm2_evictcontrol -C o -c "$CTX" 0x81010001 >/dev/null 2>&1 || true

################################
# HASHES GERADOS
################################
MD5=$(md5sum "$PUBKEY" | awk '{print $1}')
SHA1=$(sha1sum "$PUBKEY" | awk '{print $1}')
SHA256=$(sha256sum "$PUBKEY" | awk '{print $1}')

################################
# DISCORD (APENAS RESULTADO)
################################
read -r -d '' PAYLOAD <<EOF
{
  "content": "**🔐 HYDRA TPM — RESULTADO FINAL**\n\n👤 **Discord:** $DISCORD_NICK\n🕒 **Execução:** $EXEC_DATE\n🆔 **ExecID:** $EXEC_ID\n\n**🔑 CÓDIGOS GERADOS**\n\`\`\`\nMD5:     $MD5\nSHA1:    $SHA1\nSHA256:  $SHA256\n\`\`\`\n✅ **TPM processado com sucesso**"
}
EOF

curl -s -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" >/dev/null

################################
# FINAL
################################
sleep 5
reboot -f
