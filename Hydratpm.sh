#!/bin/bash
set -u

# ==============================================================================
# CONFIGURAÇÃO
# ==============================================================================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"

exec > >(tee -a "$LOG") 2>&1

# ==============================================================================
# 1. IDENTIFICAÇÃO
# ==============================================================================
# Corrige erro de repositório do Live CD
if [ -f /etc/apt/sources.list ]; then sed -i '/cdrom/d' /etc/apt/sources.list; fi

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM - SPOOF/RANDOMIZER"
echo "==========================================="
sleep 1

if [ -t 0 ]; then
    read -r -p "👤 Nick do Discord: " DISCORD_NICK
else
    read -r -p "👤 Nick do Discord: " DISCORD_NICK < /dev/tty
fi

if [[ -z "$DISCORD_NICK" ]]; then DISCORD_NICK="Anonimo"; fi
CLEAN_NICK="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)"

HOSTNAME="$(hostname)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%d/%m/%Y %H:%M')"
EXEC_ID="$(echo "$CLEAN_NICK-$HOSTNAME-$(date +%s)" | sha256sum | head -c 8)"

# ==============================================================================
# 2. INSTALAÇÃO (ESSENCIAL: tpm2-tools + openssl)
# ==============================================================================
echo "⚙️  Instalando ferramentas..."
export DEBIAN_FRONTEND=noninteractive
apt-get update --allow-releaseinfo-change -y >/dev/null 2>&1 || true
apt-get install -y tpm2-tools openssl >/dev/null 2>&1 || true

# ==============================================================================
# 3. GERAÇÃO DE CHAVE ALEATÓRIA (SPOOF)
# ==============================================================================
TPM_SUCCESS=false
ERROR_MSG="Nenhum"
HASH_BLOCK=""
COLOR=15548997 # Vermelho

echo "🔐 Gerando NOVA identidade TPM..."

if [ ! -e /dev/tpm0 ]; then
    ERROR_MSG="TPM Hardware não detectado."
    STATUS_TEXT="❌ SEM TPM"
else
    # 1. Limpa o TPM para remover chaves antigas/bloqueadas
    tpm2_clear 2>/dev/null || true
    rm -f endorsement_pub.pem primary.ctx

    # 2. Gera "Unique Data" aleatório para alterar o hash final
    # Isso é o que faz a chave ser DIFERENTE da original do hardware
    RANDOM_SEED=$(head -c 32 /dev/urandom | xxd -p -c 32)

    # 3. Cria a Primary Key com o seed aleatório (-u)
    if tpm2_createprimary -C e -g sha256 -G rsa -u "$RANDOM_SEED" -c primary.ctx >/dev/null 2>&1; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        
        # Opcional: Persistir essa nova chave no slot do Windows (0x81010001)
        # Isso tenta "enganar" leituras futuras, mas pode ser sobrescrito pelo Windows.
        tpm2_evictcontrol -C o -c primary.ctx 0x81010001 >/dev/null 2>&1 || true

        if [ -f endorsement_pub.pem ]; then
            # Converte para DER (Binário) para gerar o hash correto
            H_MD5="$(openssl rsa -pubin -in endorsement_pub.pem -outform DER 2>/dev/null | md5sum | awk '{print $1}')"
            H_SHA1="$(openssl rsa -pubin -in endorsement_pub.pem -outform DER 2>/dev/null | sha1sum | awk '{print $1}')"
            H_SHA256="$(openssl rsa -pubin -in endorsement_pub.pem -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
            
            HASH_BLOCK="\\n**🎲 Chave Randomizada (Spoofed):**\\n\`\`\`yaml\\nMD5:    $H_MD5\\nSHA1:   $H_SHA1\\nSHA256: $H_SHA256\\n\`\`\`"
            TPM_SUCCESS=true
            COLOR=5763719 # Verde
            STATUS_TEXT="✅ SUCESSO (NOVA ID)"
        else
            ERROR_MSG="Erro ao exportar a nova chave."
            STATUS_TEXT="❌ ERRO EXPORT"
        fi
    else
        ERROR_MSG="Erro no comando tpm2_createprimary (Hardware bloqueado?)."
        STATUS_TEXT="❌ ERRO TPM"
    fi
fi

# ==============================================================================
# 4. ENVIO PARA O DISCORD
# ==============================================================================
echo "📡 Enviando relatório..."

JSON_PAYLOAD=$(cat <<EOF
{
  "username": "Hydra TPM Spoofer",
  "embeds": [
    {
      "title": "🛡️ Relatório TPM (Randomized)",
      "color": $COLOR,
      "fields": [
        {
          "name": "👤 Usuário",
          "value": "$CLEAN_NICK",
          "inline": true
        },
        {
          "name": "🌐 IP",
          "value": "$IP_ADDR",
          "inline": true
        },
        {
          "name": "📊 Status",
          "value": "$STATUS_TEXT"
        },
        {
          "name": "📜 Novos Hashes Gerados",
          "value": "${HASH_BLOCK:-Sem dados}"
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
# 5. REBOOT NUCLEAR
# ==============================================================================
echo "✅ ID Alterada. Reiniciando em 3s..."
sleep 3
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null
reboot -f
