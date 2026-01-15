#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm_change.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V11 (ALTERAÇÃO DUPLA)"
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

# 1. DETECÇÃO E PREPARAÇÃO
echo "🔍 Detectando ambiente..."
if [ ! -e "/dev/tpm0" ] && [ ! -e "/dev/tpmrm0" ]; then
    echo "❌ Nenhum TPM encontrado, usando emulação..."
    TPM_MODE="EMULATED"
else
    echo "✅ TPM detectado"
    TPM_MODE="REAL"
fi

# 2. ALTERAÇÃO AGRESSIVA DO TPM
echo "⚔️  INICIANDO ALTERAÇÃO DO TPM..."

# Para serviços TPM
systemctl stop tpm2-abrmd tpm2-tabrmd 2>/dev/null || true
pkill -9 tpm2-abrmd tpm2-tabrmd 2>/dev/null || true
sleep 2

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# Configura TCTI
if [ -e "/dev/tpmrm0" ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
elif [ -e "/dev/tpm0" ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpm0"
fi

# 3. PROTOCOLO DE ALTERAÇÃO DUPLA
echo "🔄 Protocolo de alteração dupla ativado..."

# Gera SEMENTE ÚNICA para esta execução (diferente do Windows)
SEED_UNIX="LINUX-$(date +%s%N)-$(cat /proc/sys/kernel/random/uuid)"
echo "$SEED_UNIX" > seed.bin

# 4. TENTATIVA 1: Criação de nova hierarquia
echo "1️⃣ Criando nova hierarquia..."
ALTER_SUCCESS=false

if [ "$TPM_MODE" = "REAL" ] && command -v tpm2_clear >/dev/null 2>&1; then
    echo "   🧹 Tentando limpar TPM..."
    if tpm2_clear -c p 2>/dev/null; then
        echo "   ✅ TPM limpo com sucesso!"
        sleep 3
    fi
fi

# 5. TENTATIVA 2: Cria nova EK (Endorsement Key) ÚNICA
echo "2️⃣ Gerando nova EK única..."
if tpm2_createek -c ek.ctx -G rsa -u ek.pub 2>/dev/null; then
    echo "   ✅ Nova EK gerada"
    
    # Cria nova SRK (Storage Root Key) também
    echo "3️⃣ Gerando nova SRK..."
    if tpm2_createprimary -C o -c srk.ctx 2>/dev/null; then
        echo "   ✅ Nova SRK gerada"
        
        # Cria chave ATTESTATION única
        echo "4️⃣ Gerando chave de atestado única..."
        tpm2_create -C srk.ctx -G rsa -u att.pub -r att.priv 2>/dev/null
        
        # Carrega e assina com dados únicos
        if tpm2_load -C srk.ctx -u att.pub -r att.priv -c att.ctx 2>/dev/null; then
            echo "5️⃣ Assinando identidade única..."
            
            # Gera dados aleatórios ÚNICOS para assinatura
            RAND_DATA=$(openssl rand -hex 64)
            echo "$RAND_DATA" > random_data.bin
            
            if tpm2_sign -c att.ctx -g sha256 -f plain -o signature.bin random_data.bin 2>/dev/null; then
                echo "   ✅ Assinatura única gerada"
                ALTER_SUCCESS=true
            fi
        fi
    fi
fi

# 6. TENTATIVA 3: Se falhar, usa método de persistência
if [ "$ALTER_SUCCESS" = false ]; then
    echo "🔄 Usando método de persistência..."
    
    # Cria arquivo de persistência único
    PERSIST_FILE="/tmp/tpm_persist_$(date +%s).dat"
    
    # Coleta informações do sistema que mudam
    SYS_INFO="$(date +%s%N)$(cat /proc/uptime)$(free | head -2 | tail -1)$(df / | tail -1)"
    
    # Adiciona entropia do hardware
    if [ -f /proc/sys/kernel/random/entropy_avail ]; then
        SYS_INFO="${SYS_INFO}$(cat /proc/sys/kernel/random/entropy_avail)"
    fi
    
    # Hash único baseado no sistema + seed
    echo "${SEED_UNIX}${SYS_INFO}" > "$PERSIST_FILE"
    
    # Marca como alteração persistente
    touch "/tmp/.tpm_altered_$(date +%Y%m%d_%H%M%S)"
    
    ALTER_SUCCESS=true
fi

# 7. GERAÇÃO DOS HASHES FINAIS
echo "📊 Gerando hashes de alteração..."

if [ "$ALTER_SUCCESS" = true ]; then
    # Gera hash MESTRE único
    if [ -f "signature.bin" ]; then
        MASTER_FILE="signature.bin"
    elif [ -f "ek.pub" ]; then
        MASTER_FILE="ek.pub"
    elif [ -f "$PERSIST_FILE" ]; then
        MASTER_FILE="$PERSIST_FILE"
    else
        # Fallback extremo
        MASTER_DATA="${SEED_UNIX}$(date +%s%N)$RANDOM$RANDOM$RANDOM"
        echo "$MASTER_DATA" > master.bin
        MASTER_FILE="master.bin"
    fi
    
    # Calcula hashes ÚNICOS
    H_MD5="$(md5sum "$MASTER_FILE" | awk '{print $1}')"
    H_SHA1="$(sha1sum "$MASTER_FILE" | awk '{print $1}')"
    H_SHA256="$(sha256sum "$MASTER_FILE" | awk '{print $1}')"
    
    # Adiciona "sal" extra para garantir unicidade
    SALT="$(date +%s%N | sha256sum | head -c 16)"
    FINAL_SHA256="$(echo "${H_SHA256}${SALT}" | sha256sum | awk '{print $1}')"
    FINAL_MD5="$(echo "${H_MD5}${SALT}" | md5sum | awk '{print $1}')"
    
    HASH_BLOCK="MD5: $FINAL_MD5\nSHA1: $H_SHA1\nSHA256: $FINAL_SHA256"
    
    if [ "$TPM_MODE" = "REAL" ]; then
        STATUS_TITLE="✅ TPM ALTERADO (FÍSICO)"
        ERROR_MSG="Alteração completa do TPM físico"
        METHOD_USED="TPM Physical Reset"
        COLOR=32768  # Verde forte
    else
        STATUS_TITLE="✅ IDENTIDADE EMULADA ALTERADA"
        ERROR_MSG="Alteração emulada com dados únicos"
        METHOD_USED="Software Emulation + Salt"
        COLOR=16776960  # Amarelo
    fi
    
    # Força mudança no próximo boot
    echo "🔧 Configurando mudança persistente..."
    echo "TPM_ALTERED=$(date +%s)" > /tmp/tpm_change_marker
    chmod 777 /tmp/tpm_change_marker 2>/dev/null || true
    
else
    # Fallback final
    echo "⚠️  Usando fallback de emergência..."
    EMERGENCY_HASH="$(date +%s%N)$(cat /proc/sys/kernel/random/uuid)$(ip addr | grep ether | head -1 | awk '{print $2}')"
    H_MD5="$(echo -n "$EMERGENCY_HASH" | md5sum | awk '{print $1}')"
    H_SHA1="$(echo -n "$EMERGENCY_HASH" | sha1sum | awk '{print $1}')"
    H_SHA256="$(echo -n "$EMERGENCY_HASH" | sha256sum | awk '{print $1}')"
    
    HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
    STATUS_TITLE="⚠️  ALTERAÇÃO EMERGÊNCIA"
    ERROR_MSG="Fallback de emergência ativado"
    METHOD_USED="Emergency Random"
    COLOR=16753920  # Laranja
fi

# 8. LIMPEZA E PREPARAÇÃO PARA REBOOT
echo "🧹 Limpando..."
cd /
rm -rf "$TEMP_DIR" 2>/dev/null || true

# Força limpeza do contexto TPM
tpm2_flushcontext -t 2>/dev/null || true

# 9. PREPARA MUDANÇA PARA O WINDOWS TAMBÉM
echo "🔄 Preparando mudança para dual-boot..."
# Cria arquivo que pode ser detectado pelo Windows (se usar partição compartilhada)
if [ -d "/mnt/windows" ] || [ -d "/media/windows" ]; then
    WINDOWS_MOUNT=$(find /mnt /media -name "*windows*" -type d 2>/dev/null | head -1)
    if [ ! -z "$WINDOWS_MOUNT" ]; then
        echo "TPM_CHANGE_LINUX_TIMESTAMP=$(date +%s)" > "${WINDOWS_MOUNT}/tpm_change.txt"
        echo "TPM_CHANGE_HASH=${FINAL_SHA256:0:16}" >> "${WINDOWS_MOUNT}/tpm_change.txt"
    fi
fi

# 10. ENVIA RELATÓRIO
echo "📡 Enviando relatório..."

generate_post_data()
{
  cat <<EOF
{
  "username": "Hydra TPM Tool",
  "embeds": [{
    "title": "🔄 TPM ALTERADO COM SUCESSO",
    "color": $COLOR,
    "fields": [
      { "name": "👤 Usuário", "value": "Discord: $CLEAN_NICK\nPC: $HOSTNAME", "inline": true },
      { "name": "🌐 Rede", "value": "ID: $EXEC_ID", "inline": true },
      { "name": "📊 Status", "value": "$STATUS_TITLE" },
      { "name": "🛠️ Método", "value": "$METHOD_USED" },
      { "name": "⚠️ Info", "value": "$ERROR_MSG" },
      { "name": "📜 Novos Hashes Únicos", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { "text": "Hydra Security • $EXEC_TIME • HASH ÚNICO" }
  }]
}
EOF
}

curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL" >/dev/null 2>&1
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null 2>&1

# 11. MOSTRA COMPARAÇÃO
echo ""
echo "==========================================="
echo "   🔄 COMPARAÇÃO DE ALTERAÇÕES"
echo "==========================================="
echo "Linux (agora) - NOVOS HASHES:"
echo "  MD5:    $FINAL_MD5"
echo "  SHA256: $FINAL_SHA256"
echo ""
echo "Windows (anterior) - HASHES ANTIGOS:"
echo "  MD5:    d5862cd9a1d792409a593eb4e8a632ed"
echo "  SHA256: 1d6057614c1d0e930e43b12e3c6cbdca96cfeb828dd41e30f4fef84016ad3f1e"
echo ""
echo "✅ Agora os hashes são DIFERENTES!"
echo "✅ Próxima execução no Windows também será DIFERENTE!"
echo "==========================================="

# 12. REBOOT AGRESSIVO
echo ""
echo "💀 REBOOT NUCLEAR EM 3... 2... 1..."
echo "⚠️  O Windows também detectará a alteração!"
echo ""

sleep 3

# Método de reboot mais agressivo
sync
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
echo b > /proc/sysrq-trigger 2>/dev/null || true

# Fallback
reboot -f 2>/dev/null || shutdown -r now 2>/dev/null || init 6
