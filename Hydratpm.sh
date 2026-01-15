#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V7 (DAEMON SERVICE)"
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

# 1. VERIFICAÇÃO DE HARDWARE (Para não perder tempo se não tiver TPM)
echo "🔍 Verificando presença do chip TPM..."
if [ ! -d "/sys/class/tpm/tpm0" ] && [ ! -e "/dev/tpm0" ]; then
    echo "❌ ERRO FATAL: Nenhum chip TPM detectado na BIOS."
    ERROR_MSG="Chip TPM não existe ou está desativado na BIOS."
    STATUS_TITLE="❌ HARDWARE AUSENTE"
    HASH_BLOCK="N/A"
    
    # Pula direto para o envio do erro
    goto_error=true
else
    echo "✅ Chip detectado. Configurando ambiente..."
    goto_error=false
fi

if [ "$goto_error" = false ]; then
    # 2. Correção de Repositórios e Instalação do DAEMON (ABRMD)
    if [ -f /etc/apt/sources.list ]; then sed -i '/cdrom/d' /etc/apt/sources.list 2>/dev/null || true; fi
    export DEBIAN_FRONTEND=noninteractive
    
    echo "⚙️  Instalando Serviço TPM2-ABRMD..."
    apt-get update -qq >/dev/null
    # Instala o Broker (Daemon) e a biblioteca correta
    apt-get install -y tpm2-tools tpm2-abrmd libtss2-tcti-tabrmd0 curl -qq >/dev/null || true

    # 3. Configuração do Serviço
    echo "🔌 Iniciando Daemon de Acesso..."
    # Adiciona usuário tss (se necessário) e reinicia serviço
    service tpm2-abrmd stop 2>/dev/null || true
    # Força permissão no socket
    mkdir -p /run/tpm2-abrmd || true
    chmod 777 /run/tpm2-abrmd || true
    
    # Tenta iniciar o serviço pelo systemctl ou service
    systemctl restart tpm2-abrmd 2>/dev/null || service tpm2-abrmd restart 2>/dev/null || true
    sleep 3 # Espera o serviço subir

    # 4. Define o backend para usar o Daemon (tabrmd)
    export TPM2TOOLS_TCTI="tabrmd:bus_name=com.intel.tss2.Tabrmd"

    TPM_SUCCESS=false
    ERROR_MSG="Erro desconhecido"
    
    # Teste de conexão simples
    echo "🔐 Testando comunicação..."
    if ! tpm2_getcap properties-fixed >/dev/null 2>&1; then
        # Se o daemon falhar, tenta fallback para device direto
        echo "⚠️ Daemon falhou. Tentando device direto..."
        export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
    fi

    # 5. Execução Principal
    echo "🔐 Gerando nova identidade..."
    
    # Limpa
    tpm2_clear 2>/dev/null || true
    
    # Entropia
    dd if=/dev/urandom of=entropy.dat bs=32 count=1 2>/dev/null
    
    # Tenta criar chave
    if OUTPUT=$(tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat 2>&1); then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        rm entropy.dat 2>/dev/null
        
        # Sucesso
        TPM_SUCCESS=true
        
        # Gera Hashes
        H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
        H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
        
        HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
        STATUS_TITLE="✅ SUCESSO - SERIAL ALTERADO"
        ERROR_MSG="Operação Realizada com Sucesso via $TPM2TOOLS_TCTI"
        COLOR=5763719
    else
        # Falha
        TPM_SUCCESS=false
        ERROR_MSG="ERRO TPM: $(echo "$OUTPUT" | tail -n 1 | tr -d '"')"
        STATUS_TITLE="❌ FALHA DE COMUNICAÇÃO"
        HASH_BLOCK="N/A"
        COLOR=15548997
    fi
fi

# Se caiu no erro de hardware inicial
if [ "$goto_error" = true ]; then
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
