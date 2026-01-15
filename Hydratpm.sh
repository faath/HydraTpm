#!/bin/bash
set -u

# ==============================================================================
# CONFIGURAÇÃO
# ==============================================================================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"

# Grava tudo no log e mostra na tela
exec > >(tee -a "$LOG") 2>&1

# Garante que está rodando como ROOT
if [ "$EUID" -ne 0 ]; then 
  echo "❌ Por favor, rode como ROOT (sudo su)"
  exit 1
fi

# ==============================================================================
# 1. CORREÇÃO DE AMBIENTE (FIX LIVE CD)
# ==============================================================================
if [ -f /etc/apt/sources.list ]; then
    sed -i '/cdrom/d' /etc/apt/sources.list
fi

# ==============================================================================
# 2. IDENTIFICAÇÃO
# ==============================================================================
echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - LIVE MODE"
echo "==========================================="
echo ""
echo "Aguarde... Preparando input..."
sleep 1

# Input compatível com pipe e digitação manual
if [ -t 0 ]; then
    read -r -p "👤 Digite seu Nick do Discord: " DISCORD_NICK
else
    read -r -p "👤 Digite seu Nick do Discord: " DISCORD_NICK < /dev/tty
fi

if [[ -z "$DISCORD_NICK" ]]; then DISCORD_NICK="Anonimo"; fi
CLEAN_NICK="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)"

HOSTNAME="$(hostname)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%d/%m/%Y %H:%M')"
EXEC_ID="$(echo "$CLEAN_NICK-$HOSTNAME-$(date +%s)" | sha256sum | head -c 8)"

# ==============================================================================
# 3. INSTALAÇÃO DE DEPENDÊNCIAS
# ==============================================================================
echo "⚙️  Corrigindo repositórios e instalando tpm2-tools..."

export DEBIAN_FRONTEND=noninteractive

# Atualiza sem travar no erro de release
apt-get update --allow-releaseinfo-change -y >/dev/null 2>&1 || true
apt-get install -y tpm2-tools >/dev/null 2>&1 || true

# Verificação extra
if ! command -v tpm2_createprimary &> /dev/null; then
    echo "⚠️ Tentando instalação forçada..."
    apt-get update -y && apt-get install -y tpm2-tools
fi

# ==============================================================================
# 4. EXECUÇÃO TPM
# ==============================================================================
TPM_SUCCESS=false
ERROR_MSG="Nenhum"
HASH_BLOCK=""
COLOR=15548997 # Vermelho padrão

echo "🔐 Gerando chaves TPM..."

if [ ! -e /dev/tpm0 ]; then
    ERROR_MSG="Hardware TPM (/dev/tpm0) não detectado."
    STATUS_TEXT="❌ FALHA: Sem TPM Físico"
else
    tpm2_clear 2>/dev/null || true
    rm -f endorsement_pub.pem primary.ctx

    if tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx >/dev/null 2>&1; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        
        # Ruído
        tpm2_createprimary -C e -g sha1 -G rsa -c primary.ctx >/dev/null 2>&1 || true
        tpm2_evictcontrol -C o -c primary.ctx 0x81010001 >/dev/null 2>&1 || true
        
        if [ -f endorsement_pub.pem ]; then
            H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
            H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
            H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
            
            HASH_BLOCK="\\n**🔐 Hashes Gerados:**\\n\`\`\`yaml\\nMD5:    $H_MD5\\nSHA1:   $H_SHA1\\nSHA256: $H_SHA256\\n\`\`\`"
            TPM_SUCCESS=true
            COLOR=5763719 # Verde
            STATUS_TEXT="✅ SUCESSO"
        else
            ERROR_MSG="Arquivo PEM não gerado."
            STATUS_TEXT="❌ FALHA: Erro I/O"
        fi
    else
        ERROR_MSG="TPM bloqueado ou erro no comando tpm2_createprimary."
        STATUS_TEXT="❌ FALHA: Erro TPM"
    fi
fi

# ==============================================================================
# 5. ENVIO DISCORD
# ==============================================================================
echo "📡 Enviando relatório para o Discord..."

JSON_PAYLOAD=$(cat <<EOF
{
  "username": "Hydra TPM Log",
  "embeds": [
    {
      "title": "🛡️ Relatório de Execução TPM",
      "color": $COLOR,
      "fields": [
        {
          "name": "👤 Identificação",
          "value": "**User:** $CLEAN_NICK\n**Host:** $HOSTNAME",
          "inline": true
        },
        {
          "name": "🌐 Rede",
          "value": "**IP:** $IP_ADDR\n**ID:** \`$EXEC_ID\`",
          "inline": true
        },
        {
          "name": "📊 Status",
          "value": "$STATUS_TEXT"
        },
        {
          "name": "⚠️ Diagnóstico",
          "value": "${ERROR_MSG:-Nenhum}"
        },
        {
          "name": "📜 Dados",
          "value": "${HASH_BLOCK:-Nenhum hash gerado}"
        }
      ],
      "footer": {
        "text": "Hydra Security • $EXEC_TIME"
      }
    }
  ]
}
EOF
)

curl -s -H "Content-Type: application/json" -X POST -d "$JSON_PAYLOAD" "$WEBHOOK_URL" >/dev/null
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null

# ==============================================================================
# 6. FINALIZAÇÃO FORÇADA
# ==============================================================================
echo "✅ Finalizado! Reiniciando em 3 segundos..."
sleep 3

# Tenta reiniciar o serviço de log para liberar o arquivo (opcional)
service rsyslog restart >/dev/null 2>&1 || true

# Método 1: Systemctl (Padrão moderno)
systemctl reboot -i >/dev/null 2>&1 || true

# Método 2: Reboot forçado (Padrão antigo)
reboot -f >/dev/null 2>&1 || true

# Método 3: Magic SysRq (NUCLEAR - Funciona 100%)
# Isso instrui o kernel diretamente a reiniciar imediatamente
echo 1 > /proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
