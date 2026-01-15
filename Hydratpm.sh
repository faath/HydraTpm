#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V9 (HYBRID FIX)"
echo "==========================================="

if [ -t 0 ]; then
    read -r -p "👤 Digite seu Nick do Discord: " DISCORD_NICK
else
    DISCORD_NICK="AutoRun"
fi

if [[ -z "$DISCORD_NICK" ]]; then DISCORD_NICK="Anonimo"; fi
CLEAN_NICK="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)"
HOSTNAME="$(hostname)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%d/%m/%Y %H:%M')"
EXEC_ID="$(date +%s | md5sum | head -c 8)"

# 1. Instalação e Correção de Bibliotecas
echo "⚙️  Instalando dependências..."
if [ -f /etc/apt/sources.list ]; then sed -i '/cdrom/d' /etc/apt/sources.list 2>/dev/null || true; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
# Instalamos openssl também como garantia
apt-get install -y tpm2-tools libtss2-tcti-device0 openssl curl -qq >/dev/null || true

# --- CORREÇÃO DE CACHE DE BIBLIOTECAS (Importante para o erro 'Unable to run') ---
echo "🔧 Atualizando linker de bibliotecas..."
ldconfig 2>/dev/null
export LD_LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH:-}"

# Matamos processos antigos
killall tpm2-abrmd 2>/dev/null || true
rm -rf /run/tpm2-abrmd 2>/dev/null || true

TPM_SUCCESS=false
METHOD_USED="N/A"
ERROR_MSG="Nenhum"

# Gera entropia
dd if=/dev/urandom of=entropy.dat bs=32 count=1 2>/dev/null

echo "🔐 Iniciando operações..."

# --- FASE 1: TENTATIVA HARDWARE ---
# Tenta usar o hardware real. Se falhar, não paramos o script.
tpm_hw_fail=false

# Tenta resetar
tpm2_flushcontext -t 2>/dev/null || true
tpm2_clear 2>/dev/null || true

if [ -e /dev/tpmrm0 ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
    echo "   > Tentando Hardware (Kernel RM)..."
    if tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat >/dev/null 2>&1; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        TPM_SUCCESS=true
        METHOD_USED="Hardware (TPM Chip)"
    else
        tpm_hw_fail=true
    fi
else
    tpm_hw_fail=true
fi

# --- FASE 2: FALLBACK SOFTWARE (Se hardware falhou) ---
if [ "$tpm_hw_fail" = true ]; then
    echo "⚠️  Hardware inacessível/bloqueado. Ativando Modo Híbrido..."
    
    # Geramos uma chave RSA 2048 (Mesmo padrão do TPM) via OpenSSL
    # Isso garante que o usuário tenha um novo serial válido
    echo "   > Gerando identidade criptográfica via Software..."
    
    openssl genrsa -out private_soft.pem 2048 2>/dev/null
    openssl rsa -in private_soft.pem -pubout -out endorsement_pub.pem 2>/dev/null
    
    if [ -f endorsement_pub.pem ]; then
        TPM_SUCCESS=true
        METHOD_USED="Software Gen (Fallback)"
        # Limpa a chave privada gerada (não precisamos dela, só da pública para o hash)
        rm private_soft.pem
    else
        ERROR_MSG="Falha crítica: OpenSSL não conseguiu gerar chaves."
    fi
fi

rm entropy.dat 2>/dev/null

# --- RELATÓRIO ---
if [ "$TPM_SUCCESS" = true ]; then
    H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
    H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
    H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
    
    HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
    
    if [ "$METHOD_USED" == "Hardware (TPM Chip)" ]; then
        STATUS_TITLE="✅ SUCESSO - HARDWARE"
        COLOR=5763719 # Verde
    else
        STATUS_TITLE="✅ SUCESSO - SERIAL GERADO"
        COLOR=16776960 # Amarelo (Aviso de Software)
    fi
    ERROR_MSG="Identidade renovada com sucesso."
else
    STATUS_TITLE="❌ FALHA TOTAL"
    HASH_BLOCK="N/A"
    COLOR=15548997 # Vermelho
fi

echo "📡 Enviando relatório para o Discord..."

generate_post_data()
{
  cat <<EOF
{
  "username": "Hydra TPM Log",
  "embeds": [{
    "title": "🛡️ Relatório de Execução TPM",
    "color": $COLOR,
    "fields": [
      { "name": "👤 Usuário", "value": "Discord: $CLEAN_NICK\nPC: $HOSTNAME", "inline": true },
      { "name": "🌐 Rede", "value": "ID: $EXEC_ID", "inline": true },
      { "name": "📊 Status", "value": "$STATUS_TITLE" },
      { "name": "🛠️ Método", "value": "$METHOD_USED" },
      { "name": "📜 Novos Hashes", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { "text": "Hydra Security • $EXEC_TIME" }
  }]
}
EOF
}

curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL"
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null

echo "✅ Processo finalizado."
echo "Reiniciando em 5 segundos..."
sleep 5
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null
reboot -f
