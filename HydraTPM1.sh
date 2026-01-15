#!/bin/bash
set -u

# CONFIGURAÇÕES
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"

# Redireciona tudo para o log e para a tela
exec > >(tee -a "$LOG") 2>&1

#################################
# 1. IDENTIFICAÇÃO
#################################
echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - LIVE MODE"
echo "==========================================="
read -r -p "👤 Digite seu Nick do Discord: " DISCORD_NICK < /dev/tty || true

# Limpeza rigorosa do Nick para evitar quebra do JSON
if [[ -z "$DISCORD_NICK" ]]; then DISCORD_NICK="Anonimo"; fi
CLEAN_NICK="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)"

# Coleta de dados do sistema
HOSTNAME="$(hostname)"
LIVE_USER="$(whoami)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%d/%m/%Y %H:%M')"
EXEC_ID="$(echo "$CLEAN_NICK-$HOSTNAME-$(date +%s)" | sha256sum | head -c 8)"

#################################
# 2. PREPARAÇÃO E TPM
#################################
echo "⚙️  Instalando dependências (aguarde)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y tpm2-tools -qq >/dev/null || true

TPM_SUCCESS=false
ERROR_MSG="Nenhum"

echo "🔐 Iniciando operações TPM..."

if [ ! -e /dev/tpm0 ]; then
    ERROR_MSG="Dispositivo /dev/tpm0 não encontrado."
    COLOR=15548997 # Vermelho (RED)
else
    # Tenta limpar e criar as chaves
    tpm2_clear 2>/dev/null || true
    
    # Cria chave primária RSA/SHA256 (Padrão Principal) e salva PEM
    if tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx >/dev/null 2>&1; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        
        # Tentativas extras (sem falhar o script se der erro)
        tpm2_createprimary -C e -g sha1 -G rsa -c primary.ctx >/dev/null 2>&1 || true
        tpm2_createprimary -C e -g md5 -G rsa -c primary.ctx >/dev/null 2>&1 || true
        tpm2_evictcontrol -C o -c primary.ctx 0x81010001 >/dev/null 2>&1 || true
        
        TPM_SUCCESS=true
        COLOR=5763719 # Verde (GREEN)
    else
        ERROR_MSG="Falha ao criar primary key."
        COLOR=15548997 # Vermelho
    fi
fi

#################################
# 3. CÁLCULO DE HASHES
#################################
HASH_BLOCK=""
if [ -f endorsement_pub.pem ]; then
    H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
    H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
    H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
    
    HASH_BLOCK="\\n**🔐 Hashes Gerados:**\\n\`\`\`yaml\\nMD5:    $H_MD5\\nSHA1:   $H_SHA1\\nSHA256: $H_SHA256\\n\`\`\`"
else
    HASH_BLOCK="\\n⚠️ **Nenhum hash gerado** (Arquivo PEM ausente)"
fi

STATUS_TEXT="✅ SUCESSO"
if [ "$TPM_SUCCESS" = false ]; then
    STATUS_TEXT="❌ FALHA: $ERROR_MSG"
fi

#################################
# 4. ENVIO PARA DISCORD (EMBED)
#################################
echo "📡 Enviando relatório limpo para o Discord..."

# Montagem do JSON Payload (Embed)
# Nota: Usamos printf para garantir que variáveis não quebrem a estrutura
JSON_PAYLOAD=$(cat <<EOF
{
  "username": "Hydra TPM Log",
  "embeds": [
    {
      "title": "🛡️ Relatório de Execução TPM",
      "color": $COLOR,
      "fields": [
        {
          "name": "👤 Usuário",
          "value": "**Discord:** $CLEAN_NICK\n**PC:** $HOSTNAME ($LIVE_USER)",
          "inline": true
        },
        {
          "name": "🌐 Rede",
          "value": "**IP:** $IP_ADDR\n**ID:** \`$EXEC_ID\`",
          "inline": true
        },
        {
          "name": "📊 Status TPM",
          "value": "$STATUS_TEXT"
        },
        {
          "name": "📜 Detalhes",
          "value": "$HASH_BLOCK"
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

# Envia o Embed
curl -s -H "Content-Type: application/json" -X POST -d "$JSON_PAYLOAD" "$WEBHOOK_URL" >/dev/null

# Envia o log em anexo (caso precise de debug profundo)
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null

#################################
# 5. FINALIZAÇÃO
#################################
echo "✅ Concluído. Reiniciando em 5 segundos..."
sleep 5
