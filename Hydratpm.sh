#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V6 (DRIVER FIX)"
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

# 1. Correção de Repositórios e Instalação de DRIVERS
echo "⚙️  Instalando Drivers TCTI..."
if [ -f /etc/apt/sources.list ]; then sed -i '/cdrom/d' /etc/apt/sources.list 2>/dev/null || true; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
# ADICIONADO: libtss2-tcti-device0 (Fundamental para o erro 'Unable to run')
apt-get install -y tpm2-tools libtss2-tcti-device0 curl -qq >/dev/null || true

# 2. Forçar carregamento de módulos do Kernel
echo "🔌 Ativando módulos do Kernel..."
modprobe tpm_tis 2>/dev/null || true
modprobe tpm_crb 2>/dev/null || true
modprobe tpm_tis_core 2>/dev/null || true

# 3. Permissões Brutas (Garante acesso)
chmod 777 /dev/tpm* 2>/dev/null || true
chmod 777 /dev/tpmrm* 2>/dev/null || true

TPM_SUCCESS=false
ERROR_MSG="Erro desconhecido"
HASH_BLOCK="N/A"
HIERARCHY_USED="N/A"

# Função para tentar criar chave com TCTI específico
try_create_key() {
    local TCTI_VAL="$1"
    local HIERARCHY="$2"
    
    # Define o backend de comunicação
    export TPM2TOOLS_TCTI="$TCTI_VAL"
    
    # Tenta criar
    if tpm2_createprimary -C "$HIERARCHY" -g sha256 -G rsa -c primary.ctx -u entropy.dat >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

echo "🔐 Iniciando operações TPM..."

if [ ! -e /dev/tpm0 ]; then
    ERROR_MSG="Hardware TPM não detectado (Verifique BIOS)."
else
    # Gera entropia
    dd if=/dev/urandom of=entropy.dat bs=32 count=1 2>/dev/null

    # --- ESTRATÉGIA DE TENTATIVAS MÚLTIPLAS ---
    
    # 1. Tenta limpar (com configuração padrão)
    tpm2_flushcontext -t 2>/dev/null || true
    tpm2_clear 2>/dev/null || true

    # Tentativa A: Usando /dev/tpmrm0 (Resource Manager) + Hierarquia Owner
    if try_create_key "device:/dev/tpmrm0" "o"; then
        HIERARCHY_USED="Owner (via tpmrm0)"
        TPM_SUCCESS=true
        
    # Tentativa B: Usando /dev/tpm0 (Acesso Direto - Raw) + Hierarquia Owner
    # Isso resolve se o gerenciador de recursos estiver quebrado
    elif try_create_key "device:/dev/tpm0" "o"; then
        HIERARCHY_USED="Owner (Direto/Raw)"
        TPM_SUCCESS=true
        
    # Tentativa C: Hierarquia NULL (Fallback) via tpmrm0
    elif try_create_key "device:/dev/tpmrm0" "n"; then
        HIERARCHY_USED="Null (via tpmrm0)"
        TPM_SUCCESS=true
        
    # Tentativa D: Hierarquia NULL (Fallback) via tpm0
    elif try_create_key "device:/dev/tpm0" "n"; then
        HIERARCHY_USED="Null (Direto/Raw)"
        TPM_SUCCESS=true
        
    else
        # Captura erro real executando uma vez sem silenciar e sem TCTI definido (auto-detect)
        unset TPM2TOOLS_TCTI
        OUTPUT=$(tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat 2>&1)
        ERROR_MSG="FALHA TOTAL: $(echo "$OUTPUT" | tail -n 1 | tr -d '"')"
    fi
    
    rm entropy.dat 2>/dev/null

    if [ "$TPM_SUCCESS" = true ]; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        
        H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
        
        HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
        COLOR=5763719 # Verde
        STATUS_TITLE="✅ SUCESSO - SERIAL ALTERADO"
    else
        COLOR=15548997 # Vermelho
        STATUS_TITLE="❌ FALHA CRÍTICA DE HARDWARE"
    fi
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
      { "name": "🛠️ Método", "value": "$HIERARCHY_USED" },
      { "name": "⚠️ Diagnóstico", "value": "$ERROR_MSG" },
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
