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
if [ ! -e "/dev/tpm0" ]; then
    echo "❌ ERRO FATAL: /dev/tpm0 não existe. Habilite TPM na BIOS."
    ERROR_MSG="Hardware TPM não detectado."
    STATUS_TITLE="❌ HARDWARE AUSENTE"
    HASH_BLOCK="N/A"
    goto_end=true
else
    goto_end=false
fi

if [ "$goto_end" = false ]; then
    # 2. INSTALAÇÃO MASSIVA DE BIBLIOTECAS
    echo "⚙️  Instalando TODAS as libs TCTI..."
    if [ -f /etc/apt/sources.list ]; then sed -i '/cdrom/d' /etc/apt/sources.list 2>/dev/null || true; fi
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null
    
    # Instala o pacote principal E as bibliotecas de dispositivo direto
    # O segredo está no libtss2-tcti-device0 e libtss2-dev
    apt-get install -y tpm2-tools libtss2-tcti-device0 libtss2-dev curl -qq >/dev/null || true

    # 3. MATAR PROCESSOS CONCORRENTES (A "Opção Nuclear")
    echo "🔪 Matando processos conflitantes..."
    systemctl stop tpm2-abrmd 2>/dev/null || true
    killall tpm2-abrmd 2>/dev/null || true
    # Remove socket antigo se existir
    rm -rf /run/tpm2-abrmd 2>/dev/null || true

    # 4. PERMISSÕES E DRIVERS
    echo "🔌 Forçando permissões e drivers..."
    modprobe tpm_tis 2>/dev/null || true
    chmod 777 /dev/tpm0 2>/dev/null || true
    chmod 777 /dev/tpmrm0 2>/dev/null || true

    # 5. EXECUÇÃO "BRUTE FORCE"
    # Vamos tentar métodos em sequência até um funcionar
    
    TPM_SUCCESS=false
    METHOD_USED="N/A"
    
    # Gera entropia
    dd if=/dev/urandom of=entropy.dat bs=32 count=1 2>/dev/null
    
    run_tpm_attempt() {
        local TCTI_ENV="$1"
        local DESC="$2"
        echo "   > Tentando via: $DESC"
        
        # Limpa env anterior
        unset TPM2TOOLS_TCTI
        
        # Define TCTI se não for vazio
        if [ ! -z "$TCTI_ENV" ]; then
            export TPM2TOOLS_TCTI="$TCTI_ENV"
        fi
        
        # Tenta criar (usando hierarquia Owner -C o)
        if tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat >/dev/null 2>&1; then
            return 0
        fi
        return 1
    }

    echo "🔐 Tentando gerar identidade..."

    # TENTATIVA 1: Resource Manager Direto (A melhor opção para Mint)
    if run_tpm_attempt "device:/dev/tpmrm0" "Kernel RM (/dev/tpmrm0)"; then
        METHOD_USED="Kernel RM"
        TPM_SUCCESS=true
        
    # TENTATIVA 2: Device Raw (Se o RM estiver quebrado)
    elif run_tpm_attempt "device:/dev/tpm0" "Raw Device (/dev/tpm0)"; then
        METHOD_USED="Raw Device"
        TPM_SUCCESS=true
        
    # TENTATIVA 3: Auto-Detect (Sem variavel TCTI)
    elif run_tpm_attempt "" "Auto-Detect"; then
        METHOD_USED="Auto-Detect"
        TPM_SUCCESS=true
    else
        # Captura o erro da última tentativa para o log
        export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
        OUTPUT=$(tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat 2>&1)
        ERROR_MSG="FALHA V8: $(echo "$OUTPUT" | tail -n 1 | tr -d '"')"
    fi

    if [ "$TPM_SUCCESS" = true ]; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        rm entropy.dat 2>/dev/null
        
        H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
        
        HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
        STATUS_TITLE="✅ SUCESSO - SERIAL ALTERADO"
        ERROR_MSG="Sucesso via $METHOD_USED"
        COLOR=5763719
    else
        STATUS_TITLE="❌ FALHA IRRECUPERÁVEL"
        HASH_BLOCK="N/A"
        COLOR=15548997
    fi
fi

if [ "$goto_end" = true ]; then
    COLOR=15548997
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

curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL"
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null

echo "✅ Processo finalizado."
echo "Reiniciando em 5 segundos..."
sleep 5
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null
reboot -f
