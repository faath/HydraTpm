#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm.log"
# =================================================

# Redireciona tudo para o log e para a tela
exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V4 (FINAL FIX)"
echo "==========================================="

# Input do usuário
if [ -t 0 ]; then
    read -r -p "👤 Digite seu Nick do Discord: " DISCORD_NICK
else
    DISCORD_NICK="AutoRun"
fi

# Limpeza de variáveis
if [[ -z "$DISCORD_NICK" ]]; then DISCORD_NICK="Anonimo"; fi
CLEAN_NICK="$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)"
HOSTNAME="$(hostname)"
LIVE_USER="$(whoami)"
IP_ADDR="$(hostname -I | awk '{print $1}')"
EXEC_TIME="$(date '+%d/%m/%Y %H:%M')"
# Gera um ID único baseado na hora
EXEC_ID="$(date +%s | md5sum | head -c 8)"

# --- CORREÇÃO 1: Remover repositórios de CD-ROM quebrados ---
echo "⚙️  Corrigindo repositórios e instalando dependências..."
if [ -f /etc/apt/sources.list ]; then
    sed -i '/cdrom/d' /etc/apt/sources.list 2>/dev/null || true
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null
# Tenta instalar. Se falhar, continua para podermos avisar no erro.
apt-get install -y tpm2-tools curl -qq >/dev/null || true

TPM_SUCCESS=false
ERROR_MSG="Erro desconhecido"
HASH_BLOCK="N/A"

# Verifica se o tpm2 foi instalado
if ! command -v tpm2_createprimary &> /dev/null; then
    ERROR_MSG="Dependencia 'tpm2-tools' falhou ao instalar (Erro de Internet/Repo)."
    COLOR=15548997 # Vermelho
else
    echo "🔐 Iniciando operações TPM..."
    if [ ! -e /dev/tpm0 ]; then
        ERROR_MSG="Hardware TPM (/dev/tpm0) não detectado na BIOS/VM."
        COLOR=15548997
    else
        # 1. Limpa (Reseta Owner Seed)
        tpm2_clear 2>/dev/null || true
        
        # 2. Gera entropia
        dd if=/dev/urandom of=entropy.dat bs=32 count=1 2>/dev/null
        
        # 3. Cria chave Owner com entropia (Garante mudança de serial)
        # Capturamos erro se houver
        if OUTPUT=$(tpm2_createprimary -C o -g sha256 -G rsa -c primary.ctx -u entropy.dat 2>&1); then
            tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem >/dev/null 2>&1
            rm entropy.dat 2>/dev/null
            
            # Sucesso
            TPM_SUCCESS=true
            COLOR=5763719 # Verde
            ERROR_MSG="Sucesso"
            
            # Gera Hashes
            H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
            H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
            H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
            
            # Formata bloco de hashes escapando quebras de linha para JSON
            HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
        else
            # Falha no comando TPM
            ERROR_MSG="Erro TPM: $(echo "$OUTPUT" | tail -n 1 | tr -d '"')"
            COLOR=15548997
        fi
    fi
fi

# Define Status Visual
if [ "$TPM_SUCCESS" = true ]; then
    STATUS_TITLE="✅ SUCESSO - SERIAL ALTERADO"
else
    STATUS_TITLE="❌ FALHA FATAL"
fi

echo "📡 Enviando relatório para o Discord..."

# --- CORREÇÃO 2: JSON Manual Seguro ---
# Montamos o JSON linha a linha para evitar erros de formatação
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
      { "name": "⚠️ Diagnóstico", "value": "$ERROR_MSG" },
      { "name": "📜 Novos Hashes", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { "text": "Hydra Security • $EXEC_TIME" }
  }]
}
EOF
}

# Envia JSON e captura resposta para debug
curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL"
echo ""

# Envia Log File
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null

echo "✅ Processo finalizado."
echo "Reiniciando em 5 segundos..."
sleep 5
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null
reboot -f
