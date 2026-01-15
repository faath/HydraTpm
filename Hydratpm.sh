#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V5 (NULL FORCE)"
echo "==========================================="

if [ -t 0 ]; then
    read -r -p "👤 Digite seu Nick do Discord: " DISCORD_NICK
else
    DISCORD_NICK="AutoRun"
fi

if [[ -z "$DISCORD_NICK" ]]; then DISCORD_NICK="Anonimo"; fi
CLEAN_NICK="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)"
HOSTNAME="$(hostname)"
LIVE_USER="$(whoami)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%d/%m/%Y %H:%M')"
EXEC_ID="$(date +%s | md5sum | head -c 8)"

# 1. Correção de Dependências
if [ -f /etc/apt/sources.list ]; then sed -i '/cdrom/d' /etc/apt/sources.list 2>/dev/null || true; fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y tpm2-tools curl -qq >/dev/null || true

TPM_SUCCESS=false
ERROR_MSG="Erro desconhecido"
HASH_BLOCK="N/A"
HIERARCHY_USED="N/A"

# 2. Configuração TCTI (Gerenciador de Recursos)
# Isso ajuda a evitar o erro "Unable to run" gerenciando o acesso concorrente
if [ -e /dev/tpmrm0 ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
elif [ -e /dev/tpm0 ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpm0"
fi

echo "🔐 Iniciando operações TPM..."

if ! command -v tpm2_createprimary &> /dev/null; then
    ERROR_MSG="Dependencias nao instaladas."
else
    # LIMPEZA PROFUNDA: Tenta limpar contextos órfãos que causam erro de memória
    tpm2_flushcontext -t 2>/dev/null || true
    tpm2_flushcontext -l 2>/dev/null || true
    tpm2_clear 2>/dev/null || true
    
    # Gera entropia
    dd if=/dev/urandom of=entropy.dat bs=32 count=1 2>/dev/null

    # --- TENTATIVA 1: HIERARQUIA OWNER (-C o) ---
    echo "   > Tentando Hierarquia Owner..."
    if OUTPUT=$(tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat 2>&1); then
        HIERARCHY_USED="Owner (Persistente)"
        TPM_SUCCESS=true
    else
        # --- TENTATIVA 2: HIERARQUIA NULL (-C n) ---
        # Se Owner falhar (bloqueio de BIOS), usamos Null.
        # Null muda a semente a cada boot automaticamente.
        echo "   ⚠️ Owner falhou. Tentando Hierarquia Null (Force Mode)..."
        
        # Limpa novamente antes de tentar
        tpm2_flushcontext -t 2>/dev/null || true
        
        if OUTPUT=$(tpm2_createprimary -C n -g sha256 -G rsa -c primary.ctx -u entropy.dat 2>&1); then
            HIERARCHY_USED="Null (Boot-Reset)"
            TPM_SUCCESS=true
        else
            # Falha total - Captura o erro exato
            ERROR_MSG="FALHA DUPLA: $(echo "$OUTPUT" | tail -n 1 | tr -d '"')"
        fi
    fi
    
    rm entropy.dat 2>/dev/null

    # Se funcionou qualquer um dos dois métodos:
    if [ "$TPM_SUCCESS" = true ]; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        
        H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
        
        HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
        ERROR_MSG="Sucesso - Método: $HIERARCHY_USED"
        COLOR=5763719 # Verde
        STATUS_TITLE="✅ SUCESSO - SERIAL ALTERADO"
    else
        COLOR=15548997 # Vermelho
        STATUS_TITLE="❌ FALHA CRÍTICA"
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
      { "name": "🌐 Rede", "value": "IP: $IP_ADDR\nID: $EXEC_ID", "inline": true },
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
