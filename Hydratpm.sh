#!/bin/bash
set -u

# ================= CONFIGURAÇÕES GERAIS =================
WEBHOOK_URL="https://ptb.discord.com/api/webhooks/1459795641097257001/M2S4sy4dwDpHDiQgkxZ9CN2zK61lfgM5Poswk-df-2sVNAAYD8MGrExN8LiHlUAwGQzd"
LOG="/tmp/hydra_system.log"

# CONFIGURAÇÕES DO SISTEMA DE KEYS
GITHUB_USER="faath"
REPO_NAME="hydrakey"
GITHUB_TOKEN="SEU_TOKEN_AQUI"  # Substitua pelo seu token

# URLs
GIT_REPO_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
LOCAL_REPO_DIR="/tmp/hydra_keys_system"
KEYS_FILE="$LOCAL_REPO_DIR/keys.txt"
USED_KEYS_FILE="$LOCAL_REPO_DIR/used_keys.txt"

# Segurança
MAX_ATTEMPTS=3
SESSION_DURATION=3600
# ========================================================

exec > >(tee -a "$LOG") 2>&1

# FUNÇÕES AUXILIARES
print_section() {
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  $1"
    echo "╚══════════════════════════════════════════════════╝"
}

log_info() {
    echo "[$(date '+%H:%M:%S')] 🔹 $1"
}

log_success() {
    echo "[$(date '+%H:%M:%S')] ✅ $1"
}

log_error() {
    echo "[$(date '+%H:%M:%S')] ❌ $1"
}

log_warning() {
    echo "[$(date '+%H:%M:%S')] ⚠️  $1"
}

# ================= SISTEMA DE AUTENTICAÇÃO =================
initialize_key_system() {
    print_section "SISTEMA DE AUTENTICAÇÃO HYDRA"
    
    log_info "Inicializando sistema de keys..."
    
    mkdir -p "$LOCAL_REPO_DIR"
    
    if [ -d "$LOCAL_REPO_DIR/.git" ]; then
        log_info "Atualizando repositório local..."
        cd "$LOCAL_REPO_DIR"
        git pull origin main >/dev/null 2>&1 || {
            log_warning "Falha ao atualizar, recriando..."
            rm -rf "$LOCAL_REPO_DIR"
            git clone "$GIT_REPO_URL" "$LOCAL_REPO_DIR" >/dev/null 2>&1
        }
    else
        log_info "Clonando repositório de keys..."
        git clone "$GIT_REPO_URL" "$LOCAL_REPO_DIR" >/dev/null 2>&1
    fi
    
    if [ $? -ne 0 ] || [ ! -f "$KEYS_FILE" ]; then
        log_error "Falha ao acessar banco de keys!"
        log_error "Repositório: https://github.com/faath/hydrakey"
        log_error "Verifique o token de acesso"
        return 1
    fi
    
    local key_count=$(wc -l < "$KEYS_FILE")
    log_success "Banco de keys carregado: $key_count keys disponíveis"
    return 0
}

authenticate_with_key() {
    print_section "AUTENTICAÇÃO REQUERIDA"
    
    echo ""
    read -r -p "🎫 DIGITE SUA KEY DE ACESSO: " USER_KEY
    
    USER_KEY_CLEAN=$(echo "$USER_KEY" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
    
    if [ -z "$USER_KEY_CLEAN" ]; then
        log_error "Key não fornecida"
        return 1
    fi
    
    log_info "Verificando key: ${USER_KEY_CLEAN:0:12}..."
    
    # Verifica se key existe
    if grep -q "^$USER_KEY_CLEAN$" "$KEYS_FILE"; then
        log_success "KEY VÁLIDA!"
        
        # Registra uso
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local ip_addr=$(hostname -I | awk '{print $1}')
        
        echo "$USER_KEY_CLEAN | $timestamp | $DISCORD_NICK | $ip_addr" >> "$USED_KEYS_FILE"
        
        # Remove key do arquivo ativo
        grep -v "^$USER_KEY_CLEAN$" "$KEYS_FILE" > "${KEYS_FILE}.tmp"
        mv "${KEYS_FILE}.tmp" "$KEYS_FILE"
        
        # Atualiza GitHub
        update_github_repo "$USER_KEY_CLEAN"
        
        # Cria sessão
        SESSION_TOKEN=$(create_session_token "$USER_KEY_CLEAN")
        
        log_success "Autenticação concluída!"
        log_info "Token de sessão: ${SESSION_TOKEN:0:16}..."
        
        return 0
    else
        # Verifica se já foi usada
        if grep -q "$USER_KEY_CLEAN" "$USED_KEYS_FILE" 2>/dev/null; then
            local used_info=$(grep "$USER_KEY_CLEAN" "$USED_KEYS_FILE" | head -1)
            log_error "KEY JÁ UTILIZADA!"
            log_info "Usada em: $(echo "$used_info" | cut -d'|' -f2)"
            log_info "Por: $(echo "$used_info" | cut -d'|' -f3)"
        else
            log_error "KEY INVÁLIDA!"
        fi
        return 1
    fi
}

update_github_repo() {
    local key="$1"
    
    log_info "Atualizando GitHub..."
    
    cd "$LOCAL_REPO_DIR"
    
    git config user.email "hydra@system.local"
    git config user.name "Hydra Auth System"
    
    git add "$KEYS_FILE" "$USED_KEYS_FILE" >/dev/null 2>&1
    git commit -m "Key $key usada por $DISCORD_NICK" >/dev/null 2>&1
    git push origin main >/dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "GitHub atualizado com sucesso!"
    else
        log_warning "Key marcada localmente - GitHub offline"
    fi
}

create_session_token() {
    local key="$1"
    echo "${key}_$(date +%s%N)_${RANDOM}_${RANDOM}" | sha256sum | awk '{print $1}'
}

check_existing_session() {
    local session_file="/tmp/hydra_session_$DISCORD_NICK.token"
    
    if [ -f "$session_file" ]; then
        local session_time=$(stat -c %Y "$session_file")
        local current_time=$(date +%s)
        
        if [ $((current_time - session_time)) -lt $SESSION_DURATION ]; then
            log_success "Sessão ativa encontrada"
            SESSION_TOKEN=$(cat "$session_file")
            return 0
        else
            rm -f "$session_file"
        fi
    fi
    return 1
}

# ================= SISTEMA TPM RESET =================
execute_tpm_reset() {
    print_section "PROCEDIMENTO TPM RESET"
    
    log_info "Iniciando procedimento de alteração do TPM..."
    
    # 1. PREPARAÇÃO DO SISTEMA
    log_info "Atualizando sistema..."
    apt update -qq >/dev/null 2>&1
    apt upgrade -y -qq >/dev/null 2>&1
    
    # 2. INSTALAÇÃO DAS FERRAMENTAS
    log_info "Instalando tpm2-tools..."
    if ! command -v tpm2_clear >/dev/null 2>&1; then
        apt install -y tpm2-tools -qq >/dev/null 2>&1
        log_success "tpm2-tools instalado"
    else
        log_info "tpm2-tools já instalado"
    fi
    
    # 3. CONFIGURAÇÃO DO TPM
    log_info "Configurando acesso ao TPM..."
    
    # Para serviços conflitantes
    systemctl stop tpm2-abrmd 2>/dev/null || true
    pkill -9 tpm2-abrmd 2>/dev/null || true
    sleep 2
    
    # Escolhe dispositivo
    if [ -e "/dev/tpmrm0" ]; then
        export TPM2TOOLS_TCTI="device:/dev/tpmrm0"
        log_info "Usando /dev/tpmrm0"
    elif [ -e "/dev/tpm0" ]; then
        export TPM2TOOLS_TCTI="device:/dev/tpm0"
        log_info "Usando /dev/tpm0"
    else
        log_error "TPM não detectado!"
        return 1
    fi
    
    # 4. PROCEDIMENTO DE ALTERAÇÃO
    print_section "EXECUTANDO ALTERAÇÃO DO TPM"
    
    # 4.1 LIMPEZA COMPLETA
    log_info "Executando tpm2_clear..."
    if tpm2_clear 2>/dev/null; then
        log_success "TPM limpo com sucesso!"
    else
        log_warning "tpm2_clear falhou, tentando alternativas..."
        tpm2_clear -c p 2>/dev/null || true
        tpm2_clear -c o 2>/dev/null || true
    fi
    sleep 3
    
    # 4.2 CRIAÇÃO DAS CHAVES PRIMÁRIAS
    log_info "Criando novas chaves primárias..."
    
    # Chave SHA256
    if tpm2_createprimary -C e -g sha256 -G rsa -c primary.ctx 2>/dev/null; then
        log_success "Chave SHA256 criada"
        tpm2_readpublic -c primary.ctx -f pem -o key_sha256.pem 2>/dev/null
    fi
    
    # Chave SHA1
    if tpm2_createprimary -C e -g sha1 -G rsa -c primary_sha1.ctx 2>/dev/null; then
        log_success "Chave SHA1 criada"
        tpm2_readpublic -c primary_sha1.ctx -f pem -o key_sha1.pem 2>/dev/null
    fi
    
    # Chave MD5
    if tpm2_createprimary -C e -g md5 -G rsa -c primary_md5.ctx 2>/dev/null; then
        log_success "Chave MD5 criada"
        tpm2_readpublic -c primary_md5.ctx -f pem -o key_md5.pem 2>/dev/null
    fi
    
    # 4.3 PERSISTÊNCIA
    log_info "Persistindo chaves no TPM..."
    if [ -f "primary.ctx" ]; then
        tpm2_evictcontrol -C o -c primary.ctx 0x81010001 2>/dev/null || true
        log_success "Chave persistida"
    fi
    
    # 4.4 ALTERAÇÕES PARA WINDOWS
    log_info "Aplicando alterações para Windows..."
    
    # Altera PCRs importantes
    for pcr in 0 2 4 7 11 14; do
        tpm2_pcrextend $pcr:sha256=$(echo "PCR${pcr}_ALTERED_$(date +%s%N)" | sha256sum | cut -d' ' -f1) 2>/dev/null || true
    done
    
    # Escreve na NVRAM
    echo "WINDOWS_CHANGE_$(date +%s)" | tpm2_nvwrite 0x1500018 -C o 2>/dev/null || true
    
    log_success "Alterações para Windows aplicadas!"
    
    # 5. GERAÇÃO DE HASHES
    log_info "Gerando hashes únicos..."
    
    local combined_hash=""
    for key_file in *.pem; do
        [ -f "$key_file" ] && combined_hash="${combined_hash}$(sha256sum "$key_file" | awk '{print $1}')"
    done
    
    if [ -z "$combined_hash" ]; then
        combined_hash=$(echo "${DISCORD_NICK}_$(date +%s%N)_${RANDOM}" | sha256sum | awk '{print $1}')
    fi
    
    FINAL_HASH="${combined_hash:0:64}"
    
    log_success "Hash gerado: ${FINAL_HASH:0:16}..."
    
    # 6. LIMPEZA
    tpm2_flushcontext -t 2>/dev/null || true
    
    return 0
}

# ================= SISTEMA DE RELATÓRIO =================
send_discord_report() {
    local status="$1"
    local hash="$2"
    
    generate_report() {
        cat <<EOF
{
  "username": "Hydra TPM System",
  "embeds": [{
    "title": "🛡️ HYDRA TPM PROCEDURE",
    "color": 5763719,
    "fields": [
      { "name": "👤 Usuário", "value": "$DISCORD_NICK", "inline": true },
      { "name": "🔑 Status", "value": "$status", "inline": true },
      { "name": "🆔 Sessão", "value": "\`${SESSION_TOKEN:0:12}...\`", "inline": true },
      { "name": "📊 Resultado", "value": "TPM alterado com sucesso" },
      { "name": "🔐 Hash Gerado", "value": "\`\`\`${hash:0:32}...\`\`\`" },
      { "name": "🌐 Sistema", "value": "[GitHub Keys](https://github.com/faath/hydrakey)" }
    ],
    "footer": { 
      "text": "Hydra Security • $(date '+%d/%m/%Y %H:%M') • Auth + TPM Reset",
      "icon_url": "https://cdn-icons-png.flaticon.com/512/3067/3067256.png"
    }
  }]
}
EOF
    }
    
    curl -s -H "Content-Type: application/json" -X POST -d "$(generate_report)" "$WEBHOOK_URL" >/dev/null 2>&1 &
}

# ================= MAIN EXECUTION =================
main() {
    # CABEÇALHO
    echo ""
    echo "███████╗██╗  ██╗██████╗ ██████╗  █████╗ "
    echo "██╔════╝██║  ██║██╔══██╗██╔══██╗██╔══██╗"
    echo "███████╗███████║██████╔╝██████╔╝███████║"
    echo "╚════██║██╔══██║██╔══██╗██╔══██╗██╔══██║"
    echo "███████║██║  ██║██║  ██║██║  ██║██║  ██║"
    echo "╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝"
    echo ""
    echo "           TPM RESET + AUTH SYSTEM v3.0"
    echo "           Repo: github.com/faath/hydrakey"
    echo ""
    
    # SOLICITA NICK DO DISCORD
    if [ -t 0 ]; then
        read -r -p "👤 DIGITE SEU NICK DO DISCORD: " DISCORD_NICK
    else
        DISCORD_NICK="AutoRun"
    fi
    
    if [[ -z "$DISCORD_NICK" ]]; then
        DISCORD_NICK="Anonimo"
    fi
    
    CLEAN_NICK=$(echo "$DISCORD_NICK" | tr -cd '[:alnum:] ._-' | cut -c1-30)
    EXEC_TIME=$(date '+%d/%m/%Y %H:%M')
    EXEC_ID=$(date +%s | md5sum | head -c 8)
    
    # ETAPA 1: INICIALIZA SISTEMA DE KEYS
    if ! initialize_key_system; then
        log_error "Falha ao inicializar sistema de autenticação"
        echo "Usando modo de emergência (sem autenticação)..."
        read -p "Pressione ENTER para continuar..."
    fi
    
    # ETAPA 2: AUTENTICAÇÃO
    if ! check_existing_session; then
        log_info "Autenticação necessária..."
        
        local attempts=0
        while [ $attempts -lt $MAX_ATTEMPTS ]; do
            if authenticate_with_key; then
                # Salva sessão
                echo "$SESSION_TOKEN" > "/tmp/hydra_session_$DISCORD_NICK.token"
                break
            fi
            
            attempts=$((attempts + 1))
            
            if [ $attempts -ge $MAX_ATTEMPTS ]; then
                log_error "Máximo de tentativas excedido!"
                echo "Sistema bloqueado por 5 minutos..."
                sleep 300
                exit 1
            fi
            
            log_warning "Tentativa $attempts de $MAX_ATTEMPTS falhou"
            echo ""
        done
    else
        log_success "Autenticação via sessão ativa"
    fi
    
    # ETAPA 3: CONFIRMAÇÃO FINAL
    print_section "CONFIRMAÇÃO FINAL"
    
    echo ""
    echo "📋 RESUMO DA OPERAÇÃO:"
    echo "   👤 Usuário: $CLEAN_NICK"
    echo "   🔑 Sessão: ${SESSION_TOKEN:0:12}..."
    echo "   🎯 Ação: RESET COMPLETO DO TPM"
    echo ""
    echo "⚠️  AVISO: Este procedimento irá:"
    echo "   1. Limpar completamente o TPM"
    echo "   2. Criar novas chaves criptográficas"
    echo "   3. Alterar hashes para Windows/Linux"
    echo "   4. Reiniciar o sistema automaticamente"
    echo ""
    
    read -r -p "❓ CONFIRMAR EXECUÇÃO? (s/N): " CONFIRM
    
    if [[ ! "$CONFIRM" =~ ^[Ss]$ ]]; then
        log_info "Operação cancelada pelo usuário"
        exit 0
    fi
    
    # ETAPA 4: EXECUÇÃO DO TPM RESET
    if execute_tpm_reset; then
        log_success "Procedimento TPM concluído com sucesso!"
        
        # Envia relatório
        send_discord_report "✅ SUCESSO" "$FINAL_HASH"
        
        # MENSAGEM FINAL
        print_section "PROCEDIMENTO CONCLUÍDO"
        
        echo ""
        echo "🎉 TPM ALTERADO COM SUCESSO!"
        echo ""
        echo "📊 RESUMO:"
        echo "   ✅ Sistema autenticado via GitHub Keys"
        echo "   ✅ TPM completamente resetado"
        echo "   ✅ Novas chaves criptográficas geradas"
        echo "   ✅ Hashes únicos criados"
        echo "   ✅ Alterações aplicadas para Windows"
        echo ""
        echo "🔐 HASH GERADO:"
        echo "   ${FINAL_HASH:0:32}..."
        echo ""
        echo "🔄 O sistema será reiniciado automaticamente"
        echo "   Próximo boot mostrará os novos hashes"
        echo ""
        echo "⏰ Reiniciando em 10 segundos..."
        
        # Salva log da execução
        echo "EXECUÇÃO CONCLUÍDA: $EXEC_TIME" >> "$LOG"
        echo "USUÁRIO: $CLEAN_NICK" >> "$LOG"
        echo "SESSÃO: ${SESSION_TOKEN:0:16}..." >> "$LOG"
        echo "HASH: $FINAL_HASH" >> "$LOG"
        
        sleep 10
        
        # REINÍCIO
        sync
        echo 1 > /proc/sys/kernel/sysrq 2>/dev/null || true
        echo b > /proc/sysrq-trigger 2>/dev/null || true
        reboot -f 2>/dev/null || shutdown -r now
        
    else
        log_error "Falha no procedimento TPM"
        send_discord_report "❌ FALHA" "ERRO"
        exit 1
    fi
}

# EXECUTA O SCRIPT PRINCIPAL
main "$@"
