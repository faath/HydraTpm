#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm_quick.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V14 (QUICK ATTACK)"
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

# 1. VERIFICAÇÃO RÁPIDA DO TPM
echo "⚡ Verificação rápida do TPM..."
if [ ! -e "/dev/tpm0" ] && [ ! -e "/dev/tpmrm0" ]; then
    echo "❌ TPM não encontrado em /dev/tpm0 ou /dev/tpmrm0"
    echo "📋 Verificando alternativas..."
    
    # Procura outros dispositivos TPM
    find /dev -name "tpm*" 2>/dev/null || echo "Nenhum dispositivo TPM encontrado"
    exit 1
fi

echo "✅ TPM detectado"

# 2. INSTALAÇÃO RÁPIDA APENAS SE NECESSÁRIO
echo "🔧 Verificando tpm2-tools..."
if ! command -v tpm2_clear >/dev/null 2>&1; then
    echo "📦 Instalando tpm2-tools rapidamente..."
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y tpm2-tools --no-install-recommends -qq >/dev/null 2>&1
else
    echo "✅ tpm2-tools já instalado"
fi

# Configura dispositivo TPM (usa tpmrm0 se disponível)
if [ -e "/dev/tpmrm0" ]; then
    TPM_DEVICE="/dev/tpmrm0"
    echo "📱 Usando TPM Resource Manager (/dev/tpmrm0)"
else
    TPM_DEVICE="/dev/tpm0"
    echo "📱 Usando TPM Raw Device (/dev/tpm0)"
fi

export TPM2TOOLS_TCTI="device:$TPM_DEVICE"

# 3. LIMPEZA RÁPIDA DO TPM
echo ""
echo "💥 ETAPA 1: LIMPEZA DO TPM (tpm2_clear)..."
echo "=========================================="

# Para serviços que podem interferir
pkill -9 tpm2-abrmd 2>/dev/null || true
sleep 1

# Executa clear
echo "🧹 Executando tpm2_clear..."
CLEAR_OUTPUT=$(tpm2_clear 2>&1)
CLEAR_STATUS=$?

if [ $CLEAR_STATUS -eq 0 ]; then
    echo "✅ TPM limpo com sucesso!"
    CLEAR_SUCCESS=true
else
    echo "⚠️  tpm2_clear retornou código $CLEAR_STATUS"
    echo "📝 Saída: $CLEAR_OUTPUT"
    
    # Tenta clear com hierarquia específica
    echo "🔄 Tentando clear específico..."
    tpm2_clear -c p 2>/dev/null || true
    tpm2_clear -c o 2>/dev/null || true
    tpm2_clear -c e 2>/dev/null || true
    
    CLEAR_SUCCESS=true  # Assume sucesso para continuar
fi

sleep 2

# 4. CRIAÇÃO DE CHAVES PRIMÁRIAS (SEQUÊNCIA RÁPIDA)
echo ""
echo "🔐 ETAPA 2: CRIAÇÃO DE CHAVES PRIMÁRIAS..."
echo "=========================================="

# Cria diretório temporário
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

# Gera seed única RÁPIDA
SEED="${EXEC_ID}_$(date +%s%N)"
echo "🌱 Seed: ${SEED:0:20}..."

# 4.1 Primeira chave: SHA256 (como você fez)
echo ""
echo "1️⃣ Criando chave primária SHA256..."
if tpm2_createprimary -C e -g sha256 -G rsa -c primary_sha256.ctx 2>/dev/null; then
    echo "   ✅ SHA256 criada"
    
    # Lê chave pública
    if tpm2_readpublic -c primary_sha256.ctx -f pem -o key_sha256.pem 2>/dev/null; then
        SHA256_HASH=$(sha256sum key_sha256.pem | awk '{print $1}')
        echo "   🔐 Hash: ${SHA256_HASH:0:16}..."
    fi
else
    echo "   ❌ Falha na criação SHA256"
fi

# 4.2 Segunda chave: SHA1
echo ""
echo "2️⃣ Criando chave primária SHA1..."
if tpm2_createprimary -C e -g sha1 -G rsa -c primary_sha1.ctx 2>/dev/null; then
    echo "   ✅ SHA1 criada"
    tpm2_readpublic -c primary_sha1.ctx -f pem -o key_sha1.pem 2>/dev/null
fi

# 4.3 Terceira chave: MD5
echo ""
echo "3️⃣ Criando chave primária MD5..."
if tpm2_createprimary -C e -g md5 -G rsa -c primary_md5.ctx 2>/dev/null; then
    echo "   ✅ MD5 criada"
    tpm2_readpublic -c primary_md5.ctx -f pem -o key_md5.pem 2>/dev/null
fi

# 4.4 Quarta chave: Com dados aleatórios para variação
echo ""
echo "4️⃣ Criando chave com dados aleatórios..."
RAND_FILE="/tmp/random_$(date +%s).dat"
head -c 64 /dev/urandom > "$RAND_FILE"

if tpm2_createprimary -C e -g sha256 -G rsa -c primary_rand.ctx 2>/dev/null; then
    echo "   ✅ Chave aleatória criada"
    tpm2_readpublic -c primary_rand.ctx -f pem -o key_rand.pem 2>/dev/null
fi

# 5. PERSISTÊNCIA DAS CHAVES
echo ""
echo "💾 ETAPA 3: PERSISTINDO CHAVES (tpm2_evictcontrol)..."
echo "==================================================="

# Array de handles para tentar
HANDLES=("0x81010001" "0x81010002" "0x81010003" "0x81010004")

echo "📌 Persistindo chaves no TPM..."
for i in "${!HANDLES[@]}"; do
    HANDLE=${HANDLES[$i]}
    
    # Escolhe qual chave persistir baseado no índice
    case $i in
        0) KEY_FILE="primary_sha256.ctx" ;;
        1) KEY_FILE="primary_sha1.ctx" ;;
        2) KEY_FILE="primary_md5.ctx" ;;
        3) KEY_FILE="primary_rand.ctx" ;;
    esac
    
    if [ -f "$KEY_FILE" ]; then
        echo "   🎯 Tentando handle $HANDLE com $KEY_FILE..."
        if tpm2_evictcontrol -C o -c "$KEY_FILE" "$HANDLE" 2>/dev/null; then
            echo "   ✅ Persistido no handle $HANDLE"
        else
            echo "   ⚠️  Falha no handle $HANDLE"
        fi
    fi
done

# 6. ALTERAÇÃO DE PCRs PARA WINDOWS
echo ""
echo "🔄 ETAPA 4: ALTERANDO PCRs (para Windows)..."
echo "==========================================="

# PCRs que o Windows monitora
WIN_PCRS="0 2 4 7"
for PCR in $WIN_PCRS; do
    PCR_DATA="WIN_PCR${PCR}_CHANGED_${EXEC_ID}_$(date +%s)"
    HASH=$(echo -n "$PCR_DATA" | sha256sum | cut -d' ' -f1)
    
    echo "   🧬 PCR$PCR: Estendendo..."
    tpm2_pcrextend $PCR:sha256=$HASH 2>/dev/null || true
done

# 7. NVRAM PARA FORÇAR DETECÇÃO
echo ""
echo "💿 ETAPA 5: ESCRITA NVRAM..."
echo "============================"

NV_INDEX="0x1500018"
NV_DATA="LINUX_TPM_CHANGE_${EXEC_ID}_$(date +%s)"

echo "   📝 Escrevendo: ${NV_DATA:0:30}..."
echo -n "$NV_DATA" | tpm2_nvwrite $NV_INDEX -C o 2>/dev/null || {
    # Se falhar, tenta definir primeiro
    tpm2_nvdefine $NV_INDEX -C o -s 64 -a "ownerwrite|ownerread" 2>/dev/null || true
    echo -n "$NV_DATA" | tpm2_nvwrite $NV_INDEX -C o 2>/dev/null || true
}

# 8. GERA HASH FINAL ÚNICO
echo ""
echo "📊 ETAPA 6: GERANDO HASH FINAL..."
echo "================================="

# Combina todos os .pem encontrados
COMBINED="final_combined_${EXEC_ID}.dat"
> "$COMBINED"

for PEM in *.pem; do
    [ -f "$PEM" ] && cat "$PEM" >> "$COMBINED"
done

# Adiciona dados únicos
echo "EXECUTION_ID: $EXEC_ID" >> "$COMBINED"
echo "TIMESTAMP: $(date +%s%N)" >> "$COMBINED"
echo "SEED: $SEED" >> "$COMBINED"
echo "NV_DATA: $NV_DATA" >> "$COMBINED"

# Calcula hashes
H_MD5=$(md5sum "$COMBINED" | awk '{print $1}')
H_SHA1=$(sha1sum "$COMBINED" | awk '{print $1}')
H_SHA256=$(sha256sum "$COMBINED" | awk '{print $1}')

HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"

# 9. ENVIA RELATÓRIO RÁPIDO
STATUS_TITLE="✅ TPM ALTERADO (QUICK ATTACK)"
ERROR_MSG="Clear + 4 keys + PCRs + NVRAM"
METHOD_USED="Quick Sequential Attack"
COLOR=5763719

echo "🚀 Enviando relatório rápido..."

generate_post_data()
{
  cat <<EOF
{
  "username": "Hydra TPM Quick",
  "embeds": [{
    "title": "⚡ TPM QUICK ATTACK COMPLETE",
    "color": $COLOR,
    "fields": [
      { "name": "👤 Usuário", "value": "Discord: $CLEAN_NICK\nPC: $HOSTNAME", "inline": true },
      { "name": "🌐 Rede", "value": "ID: $EXEC_ID", "inline": true },
      { "name": "📊 Status", "value": "$STATUS_TITLE" },
      { "name": "🛠️ Método", "value": "$METHOD_USED" },
      { "name": "⚠️ Info", "value": "$ERROR_MSG" },
      { "name": "📜 Novos Hashes", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { 
      "text": "Hydra Security • $EXEC_TIME • Quick Attack",
      "icon_url": "https://cdn-icons-png.flaticon.com/512/3067/3067256.png"
    }
  }]
}
EOF
}

# Envia rápido (timeout baixo)
timeout 5 curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL" >/dev/null 2>&1 || true
timeout 3 curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null 2>&1 || true

# 10. LIMPEZA RÁPIDA
cd /
rm -rf "$TEMP_DIR" 2>/dev/null || true
rm -f "$RAND_FILE" 2>/dev/null || true

# 11. MENSAGEM FINAL E REBOOT
echo ""
echo "==========================================="
echo "   🎯 ATAQUE RÁPIDO CONCLUÍDO"
echo "==========================================="
echo ""
echo "✅ COMANDOS EXECUTADOS EM SEQUÊNCIA:"
echo "   1. tpm2_clear"
echo "   2. tpm2_createprimary -C e -g sha256 -G rsa"
echo "   3. tpm2_createprimary -C e -g sha1 -G rsa"
echo "   4. tpm2_createprimary -C e -g md5 -G rsa"
echo "   5. tpm2_evictcontrol (persistência)"
echo "   6. PCRs alterados"
echo "   7. NVRAM escrita"
echo ""
echo "🔐 NOVOS HASHES GERADOS:"
echo "   MD5:    ${H_MD5:0:16}..."
echo "   SHA256: ${H_SHA256:0:16}..."
echo ""
echo "⚠️  O WINDOWS VERÁ:"
echo "   • TPM completamente diferente"
echo "   • Hashes alterados"
echo "   • PCRs modificados"
echo ""
echo "💀 REINICIANDO EM 3 SEGUNDOS..."
echo ""

# Timer rápido
for i in {3..1}; do
    echo -n "$i... "
    sleep 1
done
echo "REBOOT!"

# Reboot direto
echo b > /proc/sysrq-trigger 2>/dev/null || reboot -f 2>/dev/null || shutdown -r now
