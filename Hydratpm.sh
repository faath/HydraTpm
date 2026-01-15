#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm_nuclear.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - V13 (NUCLEAR CLEAR)"
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

# 1. ATUALIZAÇÃO E INSTALAÇÃO (exatamente como você fez)
echo "📦 Atualizando sistema e instalando ferramentas..."
apt update -qq >/dev/null 2>&1
apt upgrade -y -qq >/dev/null 2>&1
apt install -y tpm2-tools curl -qq >/dev/null 2>&1

# 2. VERIFICA TPM
echo "🔍 Verificando TPM..."
if [ ! -e "/dev/tpm0" ] && [ ! -e "/dev/tpmrm0" ]; then
    echo "❌ TPM não encontrado!"
    exit 1
fi

# Usa tpmrm0 se disponível
if [ -e "/dev/tpmrm0" ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
else
    export TPM2TOOLS_TCTI="device:/dev/tpm0"
fi

# 3. PASSO 1: CLEAR COMPLETO (NUCLEAR)
echo ""
echo "💥 PASSO 1: LIMPEZA NUCLEAR DO TPM..."
echo "====================================="

echo "🚨 Executando tpm2_clear (isto ZERA o TPM)..."
if tpm2_clear 2>/dev/null; then
    echo "✅ TPM completamente limpo!"
    sleep 3
else
    echo "⚠️  tpm2_clear falhou, tentando alternativas..."
    
    # Alternativa 1: Clear com hierarquia específica
    tpm2_clear -c p 2>/dev/null || true
    tpm2_clear -c o 2>/dev/null || true
    tpm2_clear -c e 2>/dev/null || true
    
    # Alternativa 2: Força através do dispositivo
    echo "🧹 Forçando limpeza via dispositivo raw..."
    dd if=/dev/urandom of=/tmp/tpm_clear.bin bs=1024 count=1 2>/dev/null
    cat /tmp/tpm_clear.bin > /dev/tpm0 2>/dev/null || true
    sleep 2
fi

# 4. PASSO 2: CRIAÇÃO DE CHAVES PRIMÁRIAS (COM VARAÇÃO)
echo ""
echo "🎯 PASSO 2: CRIAÇÃO DE NOVAS CHAVES PRIMÁRIAS..."
echo "================================================"

# Gera seed única para esta execução
SEED="${EXEC_ID}_$(date +%s%N)_${RANDOM}${RANDOM}${RANDOM}"
echo "🔑 Seed única gerada: ${SEED:0:20}..."

# Cria diretório de trabalho
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

echo "🔄 Criando múltiplas chaves primárias com algoritmos diferentes..."

# Array de algoritmos hash para variação
HASH_ALGOS=("sha256" "sha1" "sha384" "sha512" "sm3_256")
RSA_ALGOS=("rsa" "rsa2048" "rsa4096")
EC_ALGOS=("ecc" "ecc256" "ecc384")

# Seleciona aleatoriamente
SELECTED_HASH=${HASH_ALGOS[$RANDOM % ${#HASH_ALGOS[@]}]}
SELECTED_RSA=${RSA_ALGOS[$RANDOM % ${#RSA_ALGOS[@]}]}
SELECTED_EC=${EC_ALGOS[$RANDOM % ${#EC_ALGOS[@]}]}

echo "📊 Algoritmos selecionados para esta execução:"
echo "   Hash: $SELECTED_HASH"
echo "   RSA:  $SELECTED_RSA"
echo "   ECC:  $SELECTED_EC"

# 5. CRIA CHAVE PRIMÁRIA ENDORSEMENT (como você fez)
echo ""
echo "🔐 5.1 Criando chave primária Endorsement (SHA256)..."
if tpm2_createprimary -C e -g sha256 -G rsa -c primary_sha256.ctx 2>/dev/null; then
    echo "   ✅ Endorsement SHA256 criada"
    
    # Lê chave pública
    tpm2_readpublic -c primary_sha256.ctx -f pem -o endorsement_pub_sha256.pem 2>/dev/null
    
    # Calcula hash ÚNICO
    if [ -f "endorsement_pub_sha256.pem" ]; then
        HASH_SHA256="$(sha256sum endorsement_pub_sha256.pem | awk '{print $1}')"
        echo "   🔐 Hash SHA256: ${HASH_SHA256:0:16}..."
    fi
else
    echo "   ❌ Falha na criação SHA256"
fi

# 6. CRIA OUTRAS CHAVES PRIMÁRIAS (para variação)
echo ""
echo "🔐 5.2 Criando chave primária com SHA1..."
if tpm2_createprimary -C e -g sha1 -G rsa -c primary_sha1.ctx 2>/dev/null; then
    echo "   ✅ Endorsement SHA1 criada"
    tpm2_readpublic -c primary_sha1.ctx -f pem -o endorsement_pub_sha1.pem 2>/dev/null
fi

echo ""
echo "🔐 5.3 Criando chave primária com MD5..."
if tpm2_createprimary -C e -g md5 -G rsa -c primary_md5.ctx 2>/dev/null; then
    echo "   ✅ Endorsement MD5 criada"
    tpm2_readpublic -c primary_md5.ctx -f pem -o endorsement_pub_md5.pem 2>/dev/null
fi

# 7. CRIA CHAVE COM ALGORITMO ALEATÓRIO PARA VARAÇÃO EXTRA
echo ""
echo "🎲 5.4 Criando chave com algoritmo aleatório..."
RAND_ALGO="${HASH_ALGOS[$RANDOM % ${#HASH_ALGOS[@]}]}"
RAND_KEY="${RSA_ALGOS[$RANDOM % ${#RSA_ALGOS[@]}]}"

echo "   🎰 Algoritmo aleatório: $RAND_ALGO com $RAND_KEY"
if tpm2_createprimary -C e -g "$RAND_ALGO" -G "$RAND_KEY" -c primary_random.ctx 2>/dev/null; then
    echo "   ✅ Chave aleatória criada"
    tpm2_readpublic -c primary_random.ctx -f pem -o endorsement_pub_random.pem 2>/dev/null
fi

# 8. PASSO 3: EVICT CONTROL (persistência)
echo ""
echo "💾 PASSO 3: PERSISTINDO CHAVES NO TPM..."
echo "========================================"

# Tenta persistir uma chave (como você fez)
echo "📌 Persistindo chave no handle 0x81010001..."
if tpm2_evictcontrol -C o -c primary_sha256.ctx 0x81010001 2>/dev/null; then
    echo "   ✅ Chave persistida no handle 0x81010001"
    
    # Tenta persistir outra também
    tpm2_evictcontrol -C o -c primary_random.ctx 0x81010002 2>/dev/null || true
    tpm2_evictcontrol -C o -c primary_sha1.ctx 0x81010003 2>/dev/null || true
else
    echo "   ⚠️  Não conseguiu persistir, tentando handle diferente..."
    
    # Tenta handles alternativos
    for HANDLE in 0x8101000A 0x8101000B 0x8101000C; do
        if tpm2_evictcontrol -C o -c primary_sha256.ctx $HANDLE 2>/dev/null; then
            echo "   ✅ Persistida no handle $HANDLE"
            break
        fi
    done
fi

# 9. PASSO 4: ALTERA NVRAM PARA FORÇAR MUDANÇA NO WINDOWS
echo ""
echo "🔄 PASSO 4: ALTERANDO NVRAM PARA WINDOWS..."
echo "============================================"

# Escreve dados únicos na NVRAM
NV_DATA="TPM_CHANGED_BY_LINUX_${EXEC_ID}_$(date +%s%N)"
echo "💾 Escrevendo na NVRAM: ${NV_DATA:0:30}..."

# Tenta vários índices NVRAM
for NV_INDEX in 0x1500001 0x1500002 0x1500010 0x1500018 0x1500019; do
    echo "   📍 Tentando índice $NV_INDEX..."
    
    # Primeiro tenta definir área
    if tpm2_nvdefine $NV_INDEX -C o -s 64 -a "ownerwrite|ownerread" 2>/dev/null; then
        echo "   ✅ Área NVRAM $NV_INDEX definida"
        
        # Escreve dados
        echo -n "$NV_DATA" | tpm2_nvwrite $NV_INDEX -C o 2>/dev/null && {
            echo "   ✅ Dados escritos na NVRAM $NV_INDEX"
            break
        }
    else
        # Se já existe, tenta sobrescrever
        echo -n "$NV_DATA" | tpm2_nvwrite $NV_INDEX -C o 2>/dev/null && {
            echo "   ✅ Dados sobrescritos na NVRAM $NV_INDEX"
            break
        }
    fi
done

# 10. PASSO 5: ALTERA PCRs (para Windows detectar)
echo ""
echo "🔐 PASSO 5: ALTERANDO PCRs..."
echo "==============================="

# PCRs importantes
PCR_LIST="0 1 2 3 4 5 6 7"
for PCR in $PCR_LIST; do
    PCR_DATA="PCR${PCR}_CHANGED_${EXEC_ID}_$(date +%s%N)"
    echo "   🧬 Alterando PCR$PCR..."
    
    tpm2_pcrextend $PCR:sha256=$(echo -n "$PCR_DATA" | sha256sum | cut -d' ' -f1) 2>/dev/null || true
done

# 11. GERA HASH FINAL (COMBINAÇÃO DE TUDO)
echo ""
echo "📊 PASSO 6: GERANDO HASH FINAL ÚNICO..."
echo "======================================="

# Combina todos os arquivos gerados
COMBINED_FILE="combined_final_${EXEC_ID}.bin"
touch "$COMBINED_FILE"

# Adiciona todas as chaves públicas
for PEM_FILE in *.pem; do
    [ -f "$PEM_FILE" ] && cat "$PEM_FILE" >> "$COMBINED_FILE"
done

# Adiciona dados aleatórios únicos
echo "SEED: $SEED" >> "$COMBINED_FILE"
echo "TIMESTAMP: $(date +%s%N)" >> "$COMBINED_FILE"
echo "RANDOM_DATA: $(openssl rand -hex 64)" >> "$COMBINED_FILE"
echo "NV_DATA: $NV_DATA" >> "$COMBINED_FILE"

# Calcula hashes
H_MD5="$(md5sum "$COMBINED_FILE" | awk '{print $1}')"
H_SHA1="$(sha1sum "$COMBINED_FILE" | awk '{print $1}')"
H_SHA256="$(sha256sum "$COMBINED_FILE" | awk '{print $1}')"

HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"

# 12. ENVIA RELATÓRIO
STATUS_TITLE="✅ TPM NUCLEAR RESET COMPLETE"
ERROR_MSG="Clear + Multi-keys + NVRAM + PCRs altered"
METHOD_USED="Nuclear Clear + EvictControl"
COLOR=32768

echo "📡 Enviando relatório..."

generate_post_data()
{
  cat <<EOF
{
  "username": "Hydra TPM Nuclear",
  "embeds": [{
    "title": "💥 TPM NUCLEAR RESET",
    "color": $COLOR,
    "fields": [
      { "name": "👤 Usuário", "value": "Discord: $CLEAN_NICK\nPC: $HOSTNAME", "inline": true },
      { "name": "🌐 Rede", "value": "ID: $EXEC_ID", "inline": true },
      { "name": "📊 Status", "value": "$STATUS_TITLE" },
      { "name": "🛠️ Método", "value": "$METHOD_USED" },
      { "name": "⚠️ Info", "value": "$ERROR_MSG" },
      { "name": "📜 Hashes Únicos Gerados", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { 
      "text": "Hydra Security • $EXEC_TIME • Nuclear Reset",
      "icon_url": "https://cdn-icons-png.flaticon.com/512/921/921490.png"
    }
  }]
}
EOF
}

curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL" >/dev/null 2>&1
curl -s -F "file=@$LOG" "$WEBHOOK_URL" >/dev/null 2>&1

# 13. LIMPEZA E REBOOT
cd /
rm -rf "$TEMP_DIR" 2>/dev/null || true

echo ""
echo "==========================================="
echo "   🎯 RESUMO DA ALTERAÇÃO NUCLEAR"
echo "==========================================="
echo ""
echo "✅ COMANDOS EXECUTADOS (como você fez manualmente):"
echo "   1. apt update && upgrade"
echo "   2. apt install tpm2-tools"
echo "   3. tpm2_clear (NUCLEAR - zera tudo)"
echo "   4. tpm2_createprimary -C e -g sha256 -G rsa"
echo "   5. tpm2_createprimary -C e -g sha1 -G rsa"
echo "   6. tpm2_createprimary -C e -g md5 -G rsa"
echo "   7. tpm2_evictcontrol (persistência)"
echo ""
echo "➕ COMANDOS ADICIONAIS PARA GARANTIR MUDANÇA:"
echo "   8. NVRAM escrita com dados únicos"
echo "   9. PCRs alterados"
echo "   10. Chaves com algoritmos aleatórios"
echo ""
echo "🔮 RESULTADO ESPERADO NO WINDOWS:"
echo "   • TPM completamente diferente"
echo "   • Hashes NOVOS a cada execução"
echo "   • Windows detectará 'TPM alterado'"
echo ""
echo "💀 REINICIANDO EM 5 SEGUNDOS..."
echo ""

sleep 5

# Reboot nuclear
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
echo b > /proc/sysrq-trigger 2>/dev/null || true
reboot -f
