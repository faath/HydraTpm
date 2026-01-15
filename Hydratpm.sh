#!/bin/bash
set -u

# CONFIGURAÇÕES
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"

# Redireciona tudo para o log e para a tela
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V3 (OWNER FIX)"
echo "==========================================="
read -r -p "👤 Digite seu Nick do Discord: " DISCORD_NICK < /dev/tty || true

# Limpeza rigorosa do Nick
if [[ -z "$DISCORD_NICK" ]]; then DISCORD_NICK="Anonimo"; fi
CLEAN_NICK="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)"

# Coleta de dados
HOSTNAME="$(hostname)"
LIVE_USER="$(whoami)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%d/%m/%Y %H:%M')"
EXEC_ID="$(echo "$CLEAN_NICK-$HOSTNAME-$(date +%s)" | sha256sum | head -c 8)"


echo "⚙️  Instalando dependências..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
apt-get install -y tpm2-tools -qq >/dev/null || true

TPM_SUCCESS=false
ERROR_MSG="Nenhum"
CMD_LOG=""

echo "🔐 Iniciando operações TPM..."

if [ ! -e /dev/tpm0 ]; then
    ERROR_MSG="Dispositivo /dev/tpm0 não encontrado."
    COLOR=15548997 # Vermelho
else
    # 1. Limpa o TPM (Isso reseta a Owner Seed)
    echo "   > Executando Clear..."
    tpm2_clear 2>/dev/null || true
    
    # 2. Gera entropia extra
    head -c 32 /dev/urandom > entropy.dat
    
    # 3. Cria chave na hierarquia de PROPRIETÁRIO (Owner)
    # Mudança: '-C o' em vez de '-C e'. Isso evita o erro de permissão.
    echo "   > Gerando nova identidade..."
    
    # Captura a saída de erro para debug se falhar
    if CMD_OUTPUT=$(tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat 2>&1); then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        rm entropy.dat
        
        # Cria chaves extras para garantir persistência visual
        tpm2_createprimary -C o -g sha1 -G rsa -c primary.ctx >/dev/null 2>&1 || true
        
        TPM_SUCCESS=true
        COLOR=5763719 # Verde
    else
        # Pega as últimas 2 linhas do erro para mandar pro Discord
        REAL_ERROR=$(echo "$CMD_OUTPUT" | tail -n 2)
        ERROR_MSG="Erro no tpm2_createprimary: $REAL_ERROR"
        COLOR=15548997 # Vermelho
    fi
fi


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
    # Limita o tamanho da mensagem de erro para não quebrar o JSON
    SHORT_ERR=$(echo "$ERROR_MSG" | cut -c1-100)
    STATUS_TEXT="❌ FALHA: $SHORT_ERR"
fi


echo "📡 Enviando relatório para o Discord..."

# Monta o JSON com cuidado nas aspas
JSON_PAYLOAD=$(jq -n \
                  --arg title "🛡️ Relatório de Execução TPM" \
                  --arg color "$COLOR" \
                  --arg user "$CLEAN_NICK" \
                  --arg pc "$HOSTNAME ($LIVE_USER)" \
                  --arg ip "$IP_ADDR" \
                  --arg id "$EXEC_ID" \
                  --arg status "$STATUS_TEXT" \
                  --arg details "$HASH_BLOCK" \
                  --arg time "$EXEC_TIME" \
                  '{
                    username: "Hydra TPM Log",
                    embeds: [{
                      title: $title,
                      color: ($color | tonumber),
                      fields: [
                        {name: "👤 Usuário", value: ("**Discord:** " + $user + "\n**PC:** " + $pc), inline: true},
                        {name: "🌐 Rede", value: ("**IP:** " + $ip + "\n**ID:** `" + $id + "`"), inline: true},
                        {name: "📊 Status TPM", value: $status},
                        {name: "📜 Detalhes", value: $details}
                      ],
                      footer: {text: ("Hydra Security • " + $time)}
                    }]
                  }' 2>/dev/null)

# Fallback se jq não estiver instalado (usando o método antigo cat)
if [ -z "$JSON_PAYLOAD" ]; then
JSON_PAYLOAD=$(cat <<EOF
{
  "username": "Hydra TPM Log",
  "embeds": [
    {
      "title": "🛡️ Relatório de Execução TPM",
      "color": $COLOR,
      "fields": [
        { "name": "👤 Usuário", "value": "**Discord:** $CLEAN_NICK\n**PC:** $HOSTNAME ($LIVE_USER)", "inline": true },
        { "name": "🌐 Rede", "value": "**IP:** $IP_ADDR\n**ID:** \`$EXEC_ID\`", "inline": true },
        { "name": "📊 Status TPM", "value": "$STATUS_TEXT" },
        { "name": "📜 Detalhes", "value": "$HASH_BLOCK" }
      ],
      "footer": { "text": "Hydra Security • $EXEC_TIME" }
    }
  ]
}
EOF
)
fi

curl -s -H "Content-Type: application/json" -X POST -d "$JSON_PAYLOAD" "$WEBHOOK_URL" >/dev/null
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null

echo "✅ Concluído. Reiniciando em 5 segundos..."
sleep 5
