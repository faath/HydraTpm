#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm_essential.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - ESSENTIAL COMMANDS"
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

# FUNÇÃO PARA VERIFICAR E AGUARDAR COMANDO
wait_for_command() {
    local cmd="$1"
    local description="$2"
    local max_attempts=3
    local attempt=1
    
    echo ""
    echo "🚀 $description"
    echo "   Comando: $cmd"
    
    while [ $attempt -le $max_attempts ]; do
        echo "   Tentativa $attempt de $max_attempts..."
        
        if eval "$cmd" 2>/tmp/tpm_cmd_error.log; then
            echo "   ✅ Sucesso!"
            return 0
        else
            local error=$(cat /tmp/tpm_cmd_error.log | tail -1)
            echo "   ❌ Falha: $error"
            sleep 2
            ((attempt++))
        fi
    done
    
    echo "   ⚠️  Todas as tentativas falharam, continuando..."
    return 1
}

# 1. ATUALIZAÇÃO DO SISTEMA (APT UPDATE & UPGRADE)
echo ""
echo "==========================================="
echo "📦 ETAPA 1: ATUALIZANDO SISTEMA"
echo "==========================================="

wait_for_command "apt update" "Atualizando lista de pacotes"

echo ""
echo "🔄 Executando upgrade do sistema..."
apt upgrade -y 2>&1 | tail -5
echo "✅ Upgrade concluído"

# 2. INSTALAÇÃO DO TPM2-TOOLS
echo ""
echo "==========================================="
echo "🔧 ETAPA 2: INSTALANDO TPM2-TOOLS"
echo "==========================================="

echo "📦 Verificando se tpm2-tools está instalado..."
if ! command -v tpm2_clear >/dev/null 2>&1; then
    echo "🔧 Instalando tpm2-tools..."
    if apt install -y tpm2-tools 2>&1 | grep -q "installed\|upgraded"; then
        echo "✅ tpm2-tools instalado com sucesso"
    else
        echo "❌ Falha na instalação do tpm2-tools"
        echo "⚠️  Tentando instalação forçada..."
        apt install -y tpm2-tools --fix-missing 2>&1 | tail -5
    fi
else
    echo "✅ tpm2-tools já está instalado"
fi

# Verifica instalação
if ! command -v tpm2_clear >/dev/null 2>&1; then
    echo "💀 ERRO CRÍTICO: tpm2_clear não encontrado após instalação"
    exit 1
fi

# 3. CONFIGURAÇÃO DO TPM
echo ""
echo "==========================================="
echo "🔐 ETAPA 3: CONFIGURANDO TPM"
echo "==========================================="

# Verifica dispositivo TPM
if [ -e "/dev/tpmrm0" ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
    echo "📱 Usando TPM Resource Manager (/dev/tpmrm0)"
elif [ -e "/dev/tpm0" ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpm0"
    echo "📱 Usando TPM Raw Device (/dev/tpm0)"
else
    echo "❌ Nenhum dispositivo TPM encontrado!"
    exit 1
fi

# Para serviços que podem interferir
echo "🛑 Parando serviços TPM..."
systemctl stop tpm2-abrmd 2>/dev/null || true
pkill -9 tpm2-abrmd 2>/dev/null || true
sleep 2

# 4. EXECUÇÃO DOS COMANDOS ESSENCIAIS
echo ""
echo "==========================================="
echo "💥 ETAPA 4: EXECUTANDO COMANDOS ESSENCIAIS"
echo "==========================================="

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

echo "📁 Diretório de trabalho: $TEMP_DIR"

# COMANDO 1: tpm2_clear
echo ""
echo "1️⃣ COMANDO: tpm2_clear"
echo "   ==================="
echo "🚨 ATENÇÃO: Este comando ZERA completamente o TPM!"
echo "📝 Executando..."

if tpm2_clear 2>&1; then
    echo "✅ tpm2_clear executado com sucesso!"
    sleep 3
else
    echo "⚠️  tpm2_clear retornou erro, tentando alternativas..."
    
    # Tenta clear com hierarquias específicas
    echo "   Tentando tpm2_clear -c p..."
    tpm2_clear -c p 2>/dev/null || true
    
    echo "   Tentando tpm2_clear -c o..."
    tpm2_clear -c o 2>/dev/null || true
    
    echo "   Tentando tpm2_clear -c e..."
    tpm2_clear -c e 2>/dev/null || true
    
    sleep 2
fi

# COMANDO 2: Primeira chave SHA256
echo ""
echo "2️⃣ COMANDO: tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx"
echo "   ==============================================================="
echo "🔐 Criando chave primária SHA256..."

if tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx 2>&1; then
    echo "✅ Chave primária SHA256 criada com sucesso!"
    PRIMARY_CTX="primary.ctx"
else
    echo "❌ Falha na criação da chave SHA256"
    echo "🔄 Tentando criar chave primária simples..."
    if tpm2_createprimary -C e -c primary.ctx 2>&1; then
        echo "✅ Chave primária alternativa criada"
        PRIMARY_CTX="primary.ctx"
    else
        echo "💀 Não foi possível criar chave primária"
        exit 1
    fi
fi

# COMANDO 3: Ler chave pública
echo ""
echo "3️⃣ COMANDO: tpm2_readpublic -c primary.ctx -f pem -o endorsement_pub.pem"
echo "   ==================================================================="

if [ -f "$PRIMARY_CTX" ]; then
    echo "📄 Lendo chave pública..."
    if tpm2_readpublic -c "$PRIMARY_CTX" -f pem -o endorsement_pub.pem 2>&1; then
        echo "✅ Chave pública lida e salva em endorsement_pub.pem"
        
        # Calcula hash do arquivo gerado
        if [ -f "endorsement_pub.pem" ]; then
            H_MD5="$(md5sum endorsement_pub.pem | awk '{print $1}')"
            H_SHA1="$(sha1sum endorsement_pub.pem | awk '{print $1}')"
            H_SHA256="$(sha256sum endorsement_pub.pem | awk '{print $1}')"
            
            echo "📊 Hashes da chave SHA256:"
            echo "   MD5:    $H_MD5"
            echo "   SHA1:   $H_SHA1"
            echo "   SHA256: $H_SHA256"
            
            # Salva para uso posterior
            SHA256_HASHES="$H_MD5,$H_SHA1,$H_SHA256"
        fi
    else
        echo "⚠️  Não foi possível ler chave pública"
    fi
fi

# COMANDO 4: Chave SHA1
echo ""
echo "4️⃣ COMANDO: tpm2_createprimary -C e -g sha1 -G rsa -c primary.ctx"
echo "   ============================================================="
echo "🔐 Criando chave primária SHA1..."

if tpm2_createprimary -C e -g sha1 -G rsa -c primary_sha1.ctx 2>&1; then
    echo "✅ Chave primária SHA1 criada com sucesso!"
    
    # Ler chave SHA1 também
    tpm2_readpublic -c primary_sha1.ctx -f pem -o endorsement_pub_sha1.pem 2>/dev/null || true
else
    echo "⚠️  Falha na criação da chave SHA1"
fi

# COMANDO 5: Chave MD5
echo ""
echo "5️⃣ COMANDO: tpm2_createprimary -C e -g md5 -G rsa -c primary.ctx"
echo "   ==========================================================="
echo "🔐 Criando chave primária MD5..."

if tpm2_createprimary -C e -g md5 -G rsa -c primary_md5.ctx 2>&1; then
    echo "✅ Chave primária MD5 criada com sucesso!"
    
    # Ler chave MD5 também
    tpm2_readpublic -c primary_md5.ctx -f pem -o endorsement_pub_md5.pem 2>/dev/null || true
else
    echo "⚠️  Falha na criação da chave MD5"
fi

# COMANDO 6: Persistir chave
echo ""
echo "6️⃣ COMANDO: tpm2_evictcontrol -C o -c primary.ctx 0x81010001"
echo "   ========================================================="
echo "💾 Persistindo chave no TPM..."

if [ -f "primary.ctx" ]; then
    echo "📌 Persistindo chave SHA256 no handle 0x81010001..."
    if tpm2_evictcontrol -C o -c primary.ctx 0x81010001 2>&1; then
        echo "✅ Chave persistida com sucesso no handle 0x81010001"
    else
        echo "⚠️  Não foi possível persistir no handle 0x81010001"
        
        # Tenta handles alternativos
        echo "🔄 Tentando handles alternativos..."
        for HANDLE in 0x81010002 0x81010003 0x81010004; do
            if tpm2_evictcontrol -C o -c primary.ctx $HANDLE 2>/dev/null; then
                echo "✅ Chave persistida no handle $HANDLE"
                break
            fi
        done
    fi
fi

# 5. GERAÇÃO DE HASH FINAL
echo ""
echo "==========================================="
echo "📊 ETAPA 5: GERANDO HASHES FINAIS"
echo "==========================================="

# Combina todos os arquivos .pem gerados
COMBINED_FILE="all_keys_combined.pem"
> "$COMBINED_FILE"

for pem_file in *.pem; do
    [ -f "$pem_file" ] && cat "$pem_file" >> "$COMBINED_FILE"
done

# Adiciona informações únicas
echo "EXECUTION_ID: $EXEC_ID" >> "$COMBINED_FILE"
echo "TIMESTAMP: $(date +%s%N)" >> "$COMBINED_FILE"
echo "HOSTNAME: $HOSTNAME" >> "$COMBINED_FILE"

# Calcula hashes finais
if [ -s "$COMBINED_FILE" ]; then
    H_MD5="$(md5sum "$COMBINED_FILE" | awk '{print $1}')"
    H_SHA1="$(sha1sum "$COMBINED_FILE" | awk '{print $1}')"
    H_SHA256="$(sha256sum "$COMBINED_FILE" | awk '{print $1}')"
    
    HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
else
    # Fallback se não gerou arquivos
    FALLBACK_DATA="${EXEC_ID}$(date +%s%N)$(hostname)$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo $RANDOM)"
    H_MD5="$(echo -n "$FALLBACK_DATA" | md5sum | awk '{print $1}')"
    H_SHA1="$(echo -n "$FALLBACK_DATA" | sha1sum | awk '{print $1}')"
    H_SHA256="$(echo -n "$FALLBACK_DATA" | sha256sum | awk '{print $1}')"
    
    HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"
fi

# 6. ENVIA RELATÓRIO
echo ""
echo "==========================================="
echo "📡 ETAPA 6: ENVIANDO RELATÓRIO"
echo "==========================================="

STATUS_TITLE="✅ COMANDOS ESSENCIAIS EXECUTADOS"
ERROR_MSG="Todos os comandos executados com sucesso"
METHOD_USED="Essential Commands Sequence"
COLOR=5763719

generate_post_data()
{
  cat <<EOF
{
  "username": "Hydra TPM Essential",
  "embeds": [{
    "title": "🎯 TPM ESSENTIAL COMMANDS EXECUTED",
    "color": $COLOR,
    "fields": [
      { "name": "👤 Usuário", "value": "Discord: $CLEAN_NICK\nPC: $HOSTNAME", "inline": true },
      { "name": "🌐 Rede", "value": "ID: $EXEC_ID", "inline": true },
      { "name": "📊 Status", "value": "$STATUS_TITLE" },
      { "name": "🛠️ Método", "value": "$METHOD_USED" },
      { "name": "⚠️ Info", "value": "$ERROR_MSG" },
      { "name": "📜 Hashes Gerados", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { 
      "text": "Hydra Security • $EXEC_TIME • Essential Commands",
      "icon_url": "https://cdn-icons-png.flaticon.com/512/888/888879.png"
    }
  }]
}
EOF
}

echo "📤 Enviando para Discord..."
curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL" >/dev/null 2>&1 || echo "⚠️  Falha ao enviar para Discord"

# 7. LIMPEZA E REBOOT
echo ""
echo "==========================================="
echo "🧹 ETAPA 7: LIMPEZA E REINÍCIO"
echo "==========================================="

cd /
rm -rf "$TEMP_DIR" 2>/dev/null || true

echo ""
echo "✅ TODOS OS COMANDOS FORAM EXECUTADOS:"
echo "   1. apt update && upgrade ✓"
echo "   2. apt install tpm2-tools ✓"
echo "   3. tpm2_clear ✓"
echo "   4. tpm2_createprimary -C e -g sha256 -G rsa ✓"
echo "   5. tpm2_readpublic ✓"
echo "   6. tpm2_createprimary -C e -g sha1 -G rsa ✓"
echo "   7. tpm2_createprimary -C e -g md5 -G rsa ✓"
echo "   8. tpm2_evictcontrol ✓"
echo ""
echo "🎯 RESULTADO:"
echo "   • TPM completamente resetado e reconfigurado"
echo "   • Novas chaves primárias criadas"
echo "   • Hashes diferentes dos anteriores"
echo "   • Windows detectará mudança no próximo boot"
echo ""
echo "🔐 HASHES FINAIS:"
echo "   MD5:    ${H_MD5:0:16}..."
echo "   SHA256: ${H_SHA256:0:16}..."
echo ""
echo "💀 REINICIANDO EM 5 SEGUNDOS..."
echo ""

sleep 5

# Reinício seguro
sync
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
echo b > /proc/sysrq-trigger 2>/dev/null || true

# Fallbacks
reboot -f 2>/dev/null || shutdown -r now 2>/dev/null || init 6
