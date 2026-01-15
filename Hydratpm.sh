#!/bin/bash
set -u

# ==============================================================================
# CONFIGURAÇÃO
# ==============================================================================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"

exec > >(tee -a "$LOG") 2>&1

# ==============================================================================
# 1. SETUP
# ==============================================================================
if [ -f /etc/apt/sources.list ]; then sed -i '/cdrom/d' /etc/apt/sources.list; fi

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM - DEBUG & SPOOF"
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

# ==============================================================================
# 2. INSTALAÇÃO
# ==============================================================================
echo "⚙️  Instalando..."
export DEBIAN_FRONTEND=noninteractive
apt-get update --allow-releaseinfo-change -y >/dev/null 2>&1 || true
apt-get install -y tpm2-tools openssl >/dev/null 2>&1 || true

# ==============================================================================
# 3. ROTINA DE SPOOF COM TRATAMENTO DE ERRO
# ==============================================================================
TPM_SUCCESS=false
ERROR_MSG="Desconhecido"
HASH_BLOCK=""
COLOR=15548997 # Vermelho

echo "🔐 Iniciando manipulação do TPM..."

if [ ! -e /dev/tpm0 ]; then
    ERROR_MSG="Dispositivo /dev/tpm0 não encontrado."
    STATUS_TEXT="❌ SEM TPM"
else
    # --- PASSO A: LIMPEZA PROFUNDA (FLUSH) ---
    # Isso resolve o erro de "Out of memory" do TPM
    echo "   🧹 Limpando memória transiente do TPM..."
    for handle in $(tpm2_getcap handles-transient | awk '/0x/ {print $1}'); do
        tpm2_flushcontext "$handle" >/dev/null 2>&1 || true
    done
    
    tpm2_clear >/dev/null 2>&1 || true
    rm -f endorsement_pub.pem primary.ctx

    # --- PASSO B: CRIAÇÃO DA CHAVE (COM CAPTURA DE ERRO) ---
    RANDOM_SEED=$(head -c 32 /dev/urandom | xxd -p -c 32)
    
    # Tenta criar na hierarquia Endorsement (Padrão)
    # Captura a saída de erro (stderr) para a variável TPM_OUTPUT
    echo "   🎲 Tentando criar chave randomizada (Endorsement)..."
    TPM_OUTPUT=$(tpm2_createprimary -C e -g sha256 -G rsa -u "$RANDOM_SEED" -c primary.ctx 2>&1)
    EXIT_CODE=$?

    # Se falhar no Endorsement, tenta no Null (Fallback)
    if [ $EXIT_CODE -ne 0 ]; then
        echo "   ⚠️ Falha na hierarquia 'e'. Tentando 'null'..."
        ERROR_MSG="Erro Hierarquia 'e': $TPM_OUTPUT" # Guarda o erro anterior
        
        # Tenta hierarquia Null
        TPM_OUTPUT=$(tpm2_createprimary -C n -g sha256 -G rsa -u "$RANDOM_SEED" -c primary.ctx 2>&1)
        EXIT_CODE=$?
    fi

    if [ $EXIT_CODE -eq 0 ]; then
        tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
        
        if [ -f endorsement_pub.pem ]; then
            H_MD5="$(openssl rsa -pubin -in endorsement_pub.pem -outform DER 2>/dev/null | md5sum | awk '{print $1}')"
            H_SHA1="$(openssl rsa -pubin -in endorsement_pub.pem -outform DER 2>/dev/null | sha1sum | awk '{print $1}')"
            H_SHA256="$(openssl rsa -pubin -in endorsement_pub.pem -outform DER 2>/dev/null | sha256sum | awk '{print $1}')"
            
            HASH_BLOCK="\\n**🎲 Chave Randomizada (Spoofed):**\\n\`\`\`yaml\\nMD5:    $H_MD5\\nSHA1:   $H_SHA1\\nSHA256: $H_SHA256\\n\`\`\`"
            TPM_SUCCESS=true
            COLOR=5763719 # Verde
            STATUS_TEXT="✅ SUCESSO"
        else
            ERROR_MSG="Chave criada, mas arquivo PEM falhou."
            STATUS_TEXT="❌ ERRO I/O"
        fi
    else
        # Se falhou nas duas tentativas, o TPM_OUTPUT contém o motivo exato
        # Limpa caracteres estranhos do erro para não quebrar o JSON
        CLEAN_ERROR=$(echo "$TPM_OUTPUT" | tr -d '"' | head -n 1)
        ERROR_MSG="Falha Crítica: $CLEAN_ERROR"
        STATUS_TEXT="❌ ERRO COMANDO"
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
      "title": "🛡️ Relatório TPM",
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
          "name": "⚠️ Diagnóstico (Se houve erro)",
          "value": "\`$ERROR_MSG\`"
        },
        {
          "name": "📜 Hashes",
          "value": "${HASH_BLOCK:-Nenhum dado gerado}"
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
echo "✅ Processo finalizado. Reiniciando em 3s..."
sleep 3
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null
reboot -f
