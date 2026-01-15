#!/bin/bash
set -e

LOG="/tmp/tpm-reset.log"
exec > >(tee -a "$LOG") 2>&1

echo "♻️ HYDRA TPM - RESET COMPLETO"
date

export DEBIAN_FRONTEND=noninteractive

#######################################
# 1️⃣ DESFAZER CONFIGURAÇÕES (UNDO)
#######################################
echo "🧹 [1/3] Desfazendo configurações anteriores..."

# Remove handles persistentes conhecidos
for HANDLE in 0x81010001 0x81000000 0x81000001; do
    echo "🔓 Removendo handle persistente $HANDLE"
    tpm2_evictcontrol -C o -c $HANDLE 2>/dev/null || true
done

# Remove arquivos temporários
echo "🗑️ Removendo arquivos antigos..."
rm -f primary.ctx endorsement_pub.pem *.ctx *.pem

#######################################
# 2️⃣ RESET TOTAL DO TPM
#######################################
echo "🔥 [2/3] Limpando TPM (RESET TOTAL)..."

if [ ! -e /dev/tpm0 ]; then
    echo "❌ TPM não encontrado. Ative no BIOS/UEFI."
    exit 1
fi

# Limpeza completa do TPM
tpm2_clear || echo "⚠️ TPM já estava limpo ou bloqueado"

#######################################
# 3️⃣ REFAZER CONFIGURAÇÕES (SETUP)
#######################################
echo "🚀 [3/3] Recriando configurações TPM..."

echo "📦 Atualizando sistema..."
apt update && apt upgrade -y

echo "📦 Instalando tpm2-tools..."
apt install -y tpm2-tools

echo "🔑 Criando chave primária SHA-256..."
tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx

echo "📄 Exportando chave pública..."
tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem

echo "🔑 Tentando criar chave SHA-1 (fallback)..."
tpm2_createprimary -C e -g sha1 -G rsa -c primary.ctx || echo "⚠️ SHA-1 não suportado"

echo "⚠️ Tentando MD5 (esperado falhar)..."
tpm2_createprimary -C e -g md5 -G rsa -c primary.ctx || echo "❌ MD5 não suportado"

echo "📌 Fixando chave no TPM..."
tpm2_evictcontrol -C o -c primary.ctx 0x81010001 || echo "⚠️ EvictControl falhou"

#######################################
# FINALIZAÇÃO
#######################################
echo ""
echo "✅ HYDRA TPM RESET E RECONFIGURAÇÃO CONCLUÍDOS"
echo "📄 Log salvo em: $LOG"
echo "🔁 Reiniciando máquina em 10 segundos..."
sleep 10
reboot -f
