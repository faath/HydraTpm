#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V8 (NUCLEAR)"
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

# 1. VERIFICAÇÃO DE HARDWARE
echo "🔍 Verificando hardware..."
if [ ! -e "/dev/tpm0" ] && [ ! -e "/dev/tpmrm0" ]; then
    echo "❌ ERRO FATAL: /dev/tpm0 ou /dev/tpmrm0 não existem. Habilite TPM na BIOS."
    ERROR_MSG="Hardware TPM não detectado."
    STATUS_TITLE="❌ HARDWARE AUSENTE"
    HASH_BLOCK="N/A"
    METHOD_USED="N/A"
    goto_end=true
else
    goto_end=false
fi

if [ "$goto_end" = false ]; then
    # 2. INSTALAÇÃO MASSIVA DE BIBLIOTECAS
    echo "⚙️  Instalando TODAS as libs TCTI..."
    if [ -f /etc/apt/sources.list ]; then 
        sed -i '/cdrom/d' /etc/apt/sources.list 2>/dev/null || true
    fi
    
    # Detecta se é Ubuntu/Debian
    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1
        # Instala pacotes essenciais
        apt-get install -y tpm2-tools tpm2-abrmd libtss2-tcti-device0 libtss2-tcti-tabrmd0 \
                          libtss2-tcti-mssim0 libtss2-dev curl -qq >/dev/null 2>&1 || true
    fi

    # 3. MATAR PROCESSOS CONCORRENTES
    echo "🔪 Matando processos conflitantes..."
    systemctl stop tpm2-abrmd 2>/dev/null || true
    pkill -9 tpm2-abrmd 2>/dev/null || true
    pkill -9 tpm2-tabrmd 2>/dev/null || true
    # Remove socket antigo se existir
    rm -rf /run/tpm2-abrmd /run/tpm2-tabrmd 2>/dev/null || true

    # 4. PERMISSÕES E DRIVERS
    echo "🔌 Forçando permissões e drivers..."
    modprobe tpm_tis 2>/dev/null || true
    chmod 666 /dev/tpm0 2>/dev/null || true
    chmod 666 /dev/tpmrm0 2>/dev/null || true
    
    # Adiciona usuário ao grupo tss se existir
    usermod -a -G tss "$USER" 2>/dev/null || true

    # 5. EXECUÇÃO "BRUTE FORCE"
    TPM_SUCCESS=false
    METHOD_USED="N/A"
    ERROR_MSG="FALHA V8: ERROR: Unable to run tpm2_createprimary"
    
    echo "🔐 Tentando gerar identidade..."
    
    # Tenta criar diretório temporário
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || exit 1

    run_tpm_attempt() {
        local TCTI_TYPE="$1"
        local TCTI_PARAM="$2"
        local DESC="$3"
        echo "   > Tentando via: $DESC"
        
        # Limpa variáveis de ambiente
        unset TPM2TOOLS_TCTI
        unset TPM2TOOLS_TCTI_NAME
        
        # Verifica se o dispositivo existe
        if [[ "$TCTI_TYPE" == "device" ]] && [ ! -e "$TCTI_PARAM" ]; then
            echo "     ⚠️ Dispositivo $TCTI_PARAM não encontrado"
            return 1
        fi
        
        # Configura TCTI baseado no tipo
        if [[ "$TCTI_TYPE" == "device" ]]; then
            export TPM2TOOLS_TCTI="device:$TCTI_PARAM"
        elif [[ "$TCTI_TYPE" == "abrmd" ]]; then
            export TPM2TOOLS_TCTI="tabrmd"
        elif [[ "$TCTI_TYPE" == "mssim" ]]; then
            export TPM2TOOLS_TCTI="mssim"
        fi
        
        # Verifica se TPM está acessível primeiro
        if ! tpm2_getrandom 4 2>/dev/null; then
            return 1
        fi
        
        # Tenta criar chave primária
        # Usando parâmetros mais simples e compatíveis
        if tpm2_createprimary -C o -c primary.ctx 2>/dev/null; then
            return 0
        fi
        
        # Tentativa alternativa com parâmetros específicos
        if tpm2_createprimary -Q -c primary.ctx 2>/dev/null; then
            return 0
        fi
        
        return 1
    }

    # TENTATIVA 1: Resource Manager do Kernel (recomendado para Linux Mint)
    if run_tpm_attempt "device" "/dev/tpmrm0" "Kernel RM (/dev/tpmrm0)"; then
        METHOD_USED="Kernel RM (/dev/tpmrm0)"
        TPM_SUCCESS=true
        
    # TENTATIVA 2: Device Raw
    elif run_tpm_attempt "device" "/dev/tpm0" "Raw Device (/dev/tpm0)"; then
        METHOD_USED="Raw Device (/dev/tpm0)"
        TPM_SUCCESS=true
        
    # TENTATIVA 3: ABRMD Service
    elif run_tpm_attempt "abrmd" "" "ABRMD Service"; then
        METHOD_USED="ABRMD Service"
        TPM_SUCCESS=true
        
    # TENTATIVA 4: Tente sem especificar TCTI (auto-detecção)
    else
        echo "   > Tentando via: Auto-Detect"
        unset TPM2TOOLS_TCTI
        if tpm2_getrandom 4 2>/dev/null && tpm2_createprimary -C o -c primary.ctx 2>/dev/null; then
            METHOD_USED="Auto-Detect"
            TPM_SUCCESS=true
        else
            # Captura erro detalhado
            OUTPUT=$(tpm2_createprimary -C o -c primary.ctx 2>&1 | tail -5)
            ERROR_MSG="FALHA V8: $(echo "$OUTPUT" | grep -i "error\|fail\|unable" | head -1)"
            if [ -z "$ERROR_MSG" ]; then
                ERROR_MSG="FALHA V8: ERROR: Unable to run tpm2_createprimary"
            fi
        fi
    fi

    if [ "$TPM_SUCCESS" = true ]; then
        echo "   ✅ Identidade gerada com sucesso!"
        
        # Gera arquivos de hash
        if tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem 2>/dev/null; then
            H_MD5="$(md5sum endorsement_pub.pem 2>/dev/null | awk '{print $1}' || echo 'N/A')"
            H_SHA1="$(sha1sum endorsement_pub.pem 2>/dev/null | awk '{print $1}' || echo 'N/A')"
            H_SHA256="$(sha256sum endorsement_pub.pem 2>/dev/null | awk '{print $1}' || echo 'N/A')"
            
            HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
            STATUS_TITLE="✅ SUCESSO - IDENTIDADE GERADA"
            ERROR_MSG="Sucesso via $METHOD_USED"
            COLOR=5763719
        else
            HASH_BLOCK="N/A"
            STATUS_TITLE="⚠️  PARCIAL - Chave criada mas não lida"
            ERROR_MSG="Chave criada mas falha na leitura pública"
            COLOR=16776960
        fi
        
        # Limpeza
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    else
        STATUS_TITLE="❌ FALHA IRRECUPERÁVEL"
        HASH_BLOCK="N/A"
        COLOR=15548997
        # Limpeza em caso de falha
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
fi

if [ "$goto_end" = true ]; then
    COLOR=15548997
    STATUS_TITLE="❌ HARDWARE AUSENTE"
    METHOD_USED="N/A"
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
      { "name": "⚠️ Diagnóstico", "value": "$ERROR_MSG" },
      { "name": "📜 Novos Hashes", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { "text": "Hydra Security • $EXEC_TIME" }
  }]
}
EOF
}

# Envia para Discord
curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL" >/dev/null
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null 2>&1

echo "✅ Processo finalizado."
echo "Reiniciando em 5 segundos..."
sleep 5

# Reinício mais seguro
if [ -f /proc/sysrq-trigger ]; then
    echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
    echo b > /proc/sysrq-trigger 2>/dev/null || true
else
    reboot -f 2>/dev/null || shutdown -r now 2>/dev/null || true
fi
