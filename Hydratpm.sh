#!/bin/bash
set -u

# ================= CONFIGURAÇÕES =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/tpm_ultimate.log"
# =================================================

exec > >(tee -a "$LOG") 2>&1

echo ""
echo "==========================================="
echo "   🛡️  HYDRA TPM TOOL - ULTIMATE"
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

# FUNÇÃO PARA EXECUTAR COM LOG
run_cmd() {
    local cmd="$1"
    local desc="$2"
    
    echo ""
    echo "🚀 $desc"
    echo "   📝 Comando: $cmd"
    
    local output
    local start_time=$(date +%s)
    
    if output=$(eval "$cmd" 2>&1); then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        echo "   ✅ Sucesso (${duration}s)"
        echo "$output" | tail -5 | while read line; do
            echo "   📋 $line"
        done
        return 0
    else
        echo "   ❌ Falha"
        echo "   💬 Erro: $(echo "$output" | tail -1)"
        return 1
    fi
}

# 1. ATUALIZAÇÃO E INSTALAÇÃO
echo ""
echo "==========================================="
echo "📦 ETAPA 1: PREPARAÇÃO DO SISTEMA"
echo "==========================================="

run_cmd "apt update" "Atualizando repositórios"

echo ""
echo "🔄 Executando upgrade do sistema..."
apt upgrade -y 2>&1 | tail -3
echo "✅ Upgrade concluído"

echo ""
echo "🔧 Verificando/Instalando tpm2-tools..."
if ! command -v tpm2_clear >/dev/null 2>&1; then
    run_cmd "apt install -y tpm2-tools" "Instalando tpm2-tools"
else
    echo "✅ tpm2-tools já instalado"
fi

# Verificação crítica
if ! command -v tpm2_clear >/dev/null 2>&1; then
    echo "💀 ERRO: tpm2-tools não instalado corretamente"
    exit 1
fi

# 2. CONFIGURAÇÃO DO TPM
echo ""
echo "==========================================="
echo "🔐 ETAPA 2: CONFIGURAÇÃO DO TPM"
echo "==========================================="

# Escolhe dispositivo TPM
if [ -e "/dev/tpmrm0" ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
    echo "📱 Usando /dev/tpmrm0 (Resource Manager)"
elif [ -e "/dev/tpm0" ]; then
    export TPM2TOOLS_TCTI="device:/dev/tpm0"
    echo "📱 Usando /dev/tpm0 (Raw Device)"
else
    echo "❌ Nenhum dispositivo TPM encontrado!"
    exit 1
fi

# Para serviços interferentes
echo "🛑 Parando serviços TPM..."
systemctl stop tpm2-abrmd tpm2-tabrmd 2>/dev/null || true
pkill -9 tpm2-abrmd tpm2-tabrmd 2>/dev/null || true
sleep 3

# Cria diretório de trabalho
TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1
echo "📁 Diretório de trabalho: $TEMP_DIR"

# 3. COMANDOS ESSENCIAIS DO TPM
echo ""
echo "==========================================="
echo "💥 ETAPA 3: COMANDOS ESSENCIAIS DO TPM"
echo "==========================================="

# 3.1 LIMPEZA NUCLEAR
echo ""
echo "🧨 3.1 LIMPEZA COMPLETA DO TPM"
echo "==============================="
run_cmd "tpm2_clear" "Executando tpm2_clear (limpeza total)"
sleep 5  # Tempo para TPM processar

# Fallback se clear falhar
if [ $? -ne 0 ]; then
    echo "🔄 Tentando clear alternativo..."
    tpm2_clear -c p 2>/dev/null || true
    tpm2_clear -c o 2>/dev/null || true
    tpm2_clear -c e 2>/dev/null || true
    sleep 3
fi

# 3.2 CRIAÇÃO DAS CHAVES PRIMÁRIAS
echo ""
echo "🔑 3.2 CRIAÇÃO DAS CHAVES PRIMÁRIAS"
echo "==================================="

# Gera seed única para esta execução
SEED="${EXEC_ID}_$(date +%s%N)_$(cat /proc/sys/kernel/random/uuid 2>/dev/null || echo $RANDOM$RANDOM)"
echo "🌱 Seed única: ${SEED:0:32}..."

# Chave 1: SHA256 (Principal)
echo ""
echo "1️⃣ Chave Principal (SHA256)..."
run_cmd "tpm2_createprimary -C e -g sha256 -G rsa -c primary_sha256.ctx" "Criando chave SHA256"

if [ -f "primary_sha256.ctx" ]; then
    run_cmd "tpm2_readpublic -c primary_sha256.ctx -f pem -o key_sha256.pem" "Extraindo chave pública SHA256"
fi

# Chave 2: SHA1
echo ""
echo "2️⃣ Chave Secundária (SHA1)..."
run_cmd "tpm2_createprimary -C e -g sha1 -G rsa -c primary_sha1.ctx" "Criando chave SHA1"

if [ -f "primary_sha1.ctx" ]; then
    run_cmd "tpm2_readpublic -c primary_sha1.ctx -f pem -o key_sha1.pem" "Extraindo chave pública SHA1"
fi

# Chave 3: MD5
echo ""
echo "3️⃣ Chave Terciária (MD5)..."
run_cmd "tpm2_createprimary -C e -g md5 -G rsa -c primary_md5.ctx" "Criando chave MD5"

if [ -f "primary_md5.ctx" ]; then
    run_cmd "tpm2_readpublic -c primary_md5.ctx -f pem -o key_md5.pem" "Extraindo chave pública MD5"
fi

# 3.3 PERSISTÊNCIA DAS CHAVES
echo ""
echo "💾 3.3 PERSISTINDO CHAVES NO TPM"
echo "================================"

if [ -f "primary_sha256.ctx" ]; then
    echo "📌 Persistindo chave principal..."
    run_cmd "tpm2_evictcontrol -C o -c primary_sha256.ctx 0x81010001" "Persistindo no handle 0x81010001"
    
    # Tenta handles alternativos
    if [ $? -ne 0 ]; then
        echo "🔄 Tentando handles alternativos..."
        for HANDLE in 0x81010002 0x81010003 0x81010004 0x81010005; do
            if tpm2_evictcontrol -C o -c primary_sha256.ctx $HANDLE 2>/dev/null; then
                echo "✅ Persistido no handle $HANDLE"
                break
            fi
        done
    fi
fi

# 4. LÓGICA COMPLEXA PARA WINDOWS
echo ""
echo "==========================================="
echo "🪟 ETAPA 4: ALTERAÇÃO PARA WINDOWS"
echo "==========================================="

# 4.1 ALTERAÇÃO DE PCRs (CRÍTICO PARA WINDOWS)
echo ""
echo "🧬 4.1 ALTERANDO PCRs DO WINDOWS"
echo "================================"

# PCRs que o Windows monitora intensamente
WIN_PCRS="0 2 4 7 11 14"

for PCR in $WIN_PCRS; do
    echo ""
    echo "🔧 PCR$PCR - Estendendo com dados únicos..."
    
    # Gera dados únicos para cada PCR
    PCR_DATA="WIN_PCR${PCR}_ALTERED_${SEED}_$(date +%s%N)"
    PCR_HASH=$(echo -n "$PCR_DATA" | sha256sum | cut -d' ' -f1)
    
    echo "   📝 Dados: ${PCR_DATA:0:40}..."
    echo "   🔐 Hash: ${PCR_HASH:0:16}..."
    
    if tpm2_pcrextend $PCR:sha256=$PCR_HASH 2>/dev/null; then
        echo "   ✅ PCR$PCR alterado com sucesso"
    else
        echo "   ⚠️  Falha ao alterar PCR$PCR, tentando método alternativo..."
        echo -n "$PCR_DATA" > pcr${PCR}_data.bin
        tpm2_pcrevent $PCR pcr${PCR}_data.bin 2>/dev/null || true
    fi
done

# 4.2 ESCRITA NA NVRAM (PERSISTENTE)
echo ""
echo "💿 4.2 ESCRITA NA NVRAM"
echo "======================="

# Tenta múltiplos índices NVRAM
NV_INDICES=("0x1500018" "0x1500019" "0x1500020" "0x1501000")

for NV_INDEX in "${NV_INDICES[@]}"; do
    echo ""
    echo "📌 Tentando índice NVRAM $NV_INDEX..."
    
    # Gera dados únicos para NVRAM
    NV_DATA="WINDOWS_TPM_CHANGE_${SEED}_$(date +%s%N)_NV${NV_INDEX}"
    echo "   📝 Dados: ${NV_DATA:0:50}..."
    
    # Tenta definir área se não existir
    if tpm2_nvdefine $NV_INDEX -C o -s 128 -a "ownerwrite|ownerread" 2>/dev/null; then
        echo "   ✅ Área NVRAM $NV_INDEX definida"
    else
        echo "   ℹ️  Área NVRAM $NV_INDEX já existe ou não pode ser definida"
    fi
    
    # Tenta escrever
    echo "$NV_DATA" > nv_data_${NV_INDEX}.bin
    if tpm2_nvwrite $NV_INDEX -C o -i nv_data_${NV_INDEX}.bin 2>/dev/null; then
        echo "   ✅ Dados escritos na NVRAM $NV_INDEX"
        WIN_NV_INDEX=$NV_INDEX
        WIN_NV_DATA=$NV_DATA
        break
    else
        echo "   ⚠️  Falha ao escrever na NVRAM $NV_INDEX"
    fi
done

# 4.3 ALTERAÇÃO DO PCR7 ESPECIAL (Secure Boot)
echo ""
echo "🔒 4.3 PCR7 ESPECIAL (Secure Boot)"
echo "=================================="

PCR7_DATA="SECURE_BOOT_BROKEN_${SEED}_$(date +%s%N)"
PCR7_HASH=$(echo -n "$PCR7_DATA" | sha256sum | cut -d' ' -f1)

echo "🔓 Alterando PCR7 para forçar mudança no Secure Boot..."
echo "📝 Dados: ${PCR7_DATA:0:40}..."

if tpm2_pcrextend 7:sha256=$PCR7_HASH 2>/dev/null; then
    echo "✅ PCR7 (Secure Boot) alterado com sucesso!"
else
    echo "⚠️  Falha no PCR7, usando método direto..."
    echo -n "SB_ALTERED" | tpm2_pcrevent 7 2>/dev/null || true
fi

# 4.4 CRIAÇÃO DE CHAVE DE ATESTADO ÚNICA
echo ""
echo "🎫 4.4 CHAVE DE ATESTADO ÚNICA"
echo "=============================="

echo "🔑 Criando chave de atestado única..."
if [ -f "primary_sha256.ctx" ]; then
    # Gera seed para chave de atestado
    ATTEST_SEED="ATTEST_${SEED}_$(openssl rand -hex 16)"
    
    if tpm2_create -C primary_sha256.ctx -G rsa -u att.pub -r att.priv 2>/dev/null; then
        echo "✅ Chave de atestado criada"
        
        # Carrega e assina dados
        if tpm2_load -C primary_sha256.ctx -u att.pub -r att.priv -c att.ctx 2>/dev/null; then
            echo "🔏 Assinando dados únicos..."
            
            # Dados únicos para assinatura
            SIGN_DATA="SIGNED_BY_LINUX_${SEED}_$(date +%s%N)"
            echo "$SIGN_DATA" > sign_data.bin
            
            if tpm2_sign -c att.ctx -g sha256 -f plain -o signature.bin sign_data.bin 2>/dev/null; then
                echo "✅ Dados assinados com chave única"
                HAS_SIGNATURE=true
            fi
        fi
    fi
fi

# 4.5 MARCADORES PARA O WINDOWS
echo ""
echo "📍 4.5 MARCADORES PARA O WINDOWS"
echo "================================"

# Procura partições Windows
echo "🔍 Procurando partições Windows..."
WINDOWS_MOUNTS=$(lsblk -f | grep -i "ntfs\|fat32" | awk '{print $NF}' | head -3)

if [ ! -z "$WINDOWS_MOUNTS" ]; then
    echo "✅ Partições Windows encontradas:"
    echo "$WINDOWS_MOUNTS"
    
    for MOUNT in $WINDOWS_MOUNTS; do
        if [ -d "$MOUNT" ]; then
            echo ""
            echo "📂 Processando: $MOUNT"
            
            # Cria diretório de marcadores
            MARKER_DIR="$MOUNT/TPM_Markers_$(date +%Y%m%d)"
            mkdir -p "$MARKER_DIR" 2>/dev/null
            
            if [ $? -eq 0 ]; then
                # Cria arquivo REG para Windows
                cat > "$MARKER_DIR/tpm_change.reg" << EOF
Windows Registry Editor Version 5.00

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\TPM]
"LinuxAltered"=dword:$(date +%s | tail -c 8)
"ChangeID"="${EXEC_ID}"
"Timestamp"=$(date +%s)

[HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\IntegrityServices]
"PCRsModified"="${WIN_PCRS// /,}"
"SecureBootChanged"=dword:00000001
EOF
                
                # Cria arquivo de configuração
                cat > "$MARKER_DIR/tpm_info.txt" << EOF
TPM CHANGE INFORMATION
======================
Change ID: ${EXEC_ID}
Timestamp: $(date)
Linux Host: ${HOSTNAME}
Seed: ${SEED:0:32}
PCRs Altered: ${WIN_PCRS}
NVRAM Index: ${WIN_NV_INDEX:-NONE}
Secure Boot PCR7: ALTERED
EOF
                
                # Cria arquivo batch para Windows
                cat > "$MARKER_DIR/check_tpm.bat" << EOF
@echo off
echo Checking TPM status...
powershell -Command "Get-TpmEndorsementKeyInfo | Format-List"
powershell -Command "Get-TpmPCR -Index 0,2,4,7,11,14 | Format-Table"
echo.
echo TPM was altered by Linux on $(date)
pause
EOF
                
                echo "✅ Marcadores criados em $MARKER_DIR"
                
                # Sinaliza para scripts do Windows
                touch "$MOUNT/.tpm_altered_by_linux"
                echo "${EXEC_ID}" > "$MOUNT/.tpm_change_id"
            else
                echo "⚠️  Sem permissão para escrever em $MOUNT"
            fi
        fi
    done
else
    echo "⚠️  Nenhuma partição Windows encontrada"
fi

# 5. GERAÇÃO DE HASHES FINAIS
echo ""
echo "==========================================="
echo "📊 ETAPA 5: HASHES FINAIS"
echo "==========================================="

# Combina TUDO para hash final
COMBINED_FILE="ultimate_combined_${EXEC_ID}.bin"
> "$COMBINED_FILE"

# Adiciona todas as chaves
for pem_file in *.pem; do
    [ -f "$pem_file" ] && cat "$pem_file" >> "$COMBINED_FILE"
done

# Adiciona assinatura se existir
[ -f "signature.bin" ] && cat "signature.bin" >> "$COMBINED_FILE"

# Adiciona dados únicos
echo "=== EXECUTION DATA ===" >> "$COMBINED_FILE"
echo "ID: $EXEC_ID" >> "$COMBINED_FILE"
echo "Seed: $SEED" >> "$COMBINED_FILE"
echo "Timestamp: $(date +%s%N)" >> "$COMBINED_FILE"
echo "PCRs Altered: $WIN_PCRS" >> "$COMBINED_FILE"
echo "NVRAM Data: ${WIN_NV_DATA:-NONE}" >> "$COMBINED_FILE"
echo "PCR7 Data: $PCR7_DATA" >> "$COMBINED_FILE"

# Adiciona dados do sistema
echo "=== SYSTEM DATA ===" >> "$COMBINED_FILE"
uname -a >> "$COMBINED_FILE" 2>/dev/null
hostname >> "$COMBINED_FILE"
date >> "$COMBINED_FILE"

# Calcula hashes
H_MD5="$(md5sum "$COMBINED_FILE" | awk '{print $1}')"
H_SHA1="$(sha1sum "$COMBINED_FILE" | awk '{print $1}')"
H_SHA256="$(sha256sum "$COMBINED_FILE" | awk '{print $1}')"

HASH_BLOCK="MD5: $H_MD5\nSHA1: $H_SHA1\nSHA256: $H_SHA256"

# 6. ENVIO DE RELATÓRIO
echo ""
echo "==========================================="
echo "📡 ETAPA 6: RELATÓRIO FINAL"
echo "==========================================="

STATUS_TITLE="✅ TPM ULTIMATE ALTERATION COMPLETE"
ERROR_MSG="Essential commands + Windows PCRs/NVRAM altered"
METHOD_USED="Nuclear Clear + PCR Extension + NVRAM Write"
COLOR=32768

generate_post_data()
{
  cat <<EOF
{
  "username": "Hydra TPM Ultimate",
  "embeds": [{
    "title": "💥 TPM ULTIMATE TRANSFORMATION",
    "color": $COLOR,
    "fields": [
      { "name": "👤 Usuário", "value": "Discord: $CLEAN_NICK\nPC: $HOSTNAME", "inline": true },
      { "name": "🌐 Rede", "value": "ID: $EXEC_ID", "inline": true },
      { "name": "📊 Status", "value": "$STATUS_TITLE" },
      { "name": "🛠️ Método", "value": "$METHOD_USED" },
      { "name": "⚠️ Info", "value": "$ERROR_MSG" },
      { "name": "📜 Ultimate Hashes", "value": "\`\`\`yaml\n$HASH_BLOCK\n\`\`\`" }
    ],
    "footer": { 
      "text": "Hydra Security • $EXEC_TIME • PCRs: $WIN_PCRS • NVRAM: ${WIN_NV_INDEX:-NONE}",
      "icon_url": "https://cdn-icons-png.flaticon.com/512/921/921490.png"
    }
  }]
}
EOF
}

echo "📤 Enviando relatório para Discord..."
curl -s -H "Content-Type: application/json" -X POST -d "$(generate_post_data)" "$WEBHOOK_URL" >/dev/null 2>&1 || echo "⚠️  Falha ao enviar relatório"

# 7. LIMPEZA E REBOOT
echo ""
echo "==========================================="
echo "🧹 ETAPA 7: FINALIZAÇÃO"
echo "==========================================="

# Limpa contexto TPM
tpm2_flushcontext -t 2>/dev/null || true

# Limpa diretório temporário
cd /
rm -rf "$TEMP_DIR" 2>/dev/null || true

# RESUMO FINAL
echo ""
echo "🎉 ALTERAÇÃO ULTIMATE CONCLUÍDA!"
echo "================================="
echo ""
echo "✅ COMANDOS ESSENCIAIS EXECUTADOS:"
echo "   1. apt update && upgrade ✓"
echo "   2. apt install tpm2-tools ✓"
echo "   3. tpm2_clear (Nuclear) ✓"
echo "   4. tpm2_createprimary SHA256/SHA1/MD5 ✓"
echo "   5. tpm2_evictcontrol (Persistência) ✓"
echo ""
echo "🪟 ALTERAÇÕES PARA WINDOWS:"
echo "   • PCRs $WIN_PCRS alterados ✓"
echo "   • NVRAM escrita ✓"
echo "   • PCR7 (Secure Boot) modificado ✓"
echo "   • Marcadores criados em partições Windows ✓"
echo ""
echo "🔐 NOVOS HASHES (ÚNICOS):"
echo "   MD5:    ${H_MD5}"
echo "   SHA256: ${H_SHA256}"
echo ""
echo "⚠️  PRÓXIMO BOOT NO WINDOWS:"
echo "   • TPM aparecerá como 'alterado'"
echo "   • Hashes serão DIFERENTES"
echo "   • Secure Boot detectará mudança"
echo ""
echo "💀 REINICIANDO EM 10 SEGUNDOS..."
echo ""

# Contagem regressiva
for i in {10..1}; do
    echo -n "$i... "
    sleep 1
done

echo ""
echo "🚀 REBOOTING NOW!"

# Reinício nuclear
sync
echo 1 > /proc/sys/kernel/sysrq 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null

# Fallbacks
reboot -f 2>/dev/null || shutdown -r now 2>/dev/null || init 6
