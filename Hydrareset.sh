#!/bin/bash
set -e

WEBHOOK_URL="https://discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"

exec > >(tee -a "$LOG") 2>&1

echo "🚀 Iniciando execução TPM"
date

export DEBIAN_FRONTEND=noninteractive

echo "📦 Atualizando sistema..."
apt update && apt upgrade -y

echo "📦 Instalando tpm2-tools..."
apt install -y tpm2-tools

echo "🔍 Verificando TPM..."
if [ ! -e /dev/tpm0 ]; then
    echo "❌ TPM não encontrado. Ative no BIOS/UEFI."
    curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d '{"content":"❌ **HYDRA TPM**\nTPM não encontrado no sistema."}'
    exit 1
fi

echo "🔐 Limpando TPM..."
tpm2_clear || echo "⚠️ Falha ao limpar TPM"

echo "🔑 Criando primário SHA-256..."
tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx

echo "📄 Exportando chave pública..."
tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem

echo "🔑 Criando primário SHA-1..."
tpm2_createprimary -C e -g sha1 -G rsa -c primary.ctx || echo "⚠️ SHA-1 falhou"

echo "⚠️ Tentando MD5 (não suportado)..."
tpm2_createprimary -C e -g md5 -G rsa -c primary.ctx || echo "❌ MD5 não suportado (esperado)"

echo "📌 Fixando chave no TPM..."
tpm2_evictcontrol -C o -c primary.ctx 0x81010001 || echo "⚠️ EvictControl falhou"

echo "✅ Script finalizado com sucesso"

#######################################
# ENVIO DO LOG PARA O DISCORD
#######################################
echo "📡 Enviando log para o Discord..."

curl -X POST "$WEBHOOK_URL" \
  -F "payload_json={\"content\":\"✅ **HYDRA TPM FINALIZADO COM SUCESSO**\n📄 Log completo em anexo.\"}" \
  -F "file=@$LOG"

echo "🔁 Reiniciando máquina em 10 segundos..."
sleep 10
reboot -f
