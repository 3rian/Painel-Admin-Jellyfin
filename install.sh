#!/bin/bash
set -e

REPO_URL="https://raw.githubusercontent.com/3rian/Painel-Admin-Jellyfin/main"
BASE_DIR="/opt/jellyfin-expiry"
BIN_FILE="/usr/local/bin/jellyfin"
CRON_LINE="0 3 * * * $BASE_DIR/jf-expiry.sh verificar >/dev/null 2>&1"

RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
CYAN="\e[1;36m"
WHITE="\e[1;37m"
RESET="\e[0m"

msg()  { echo -e "${GREEN}$1${RESET}"; }
warn() { echo -e "${YELLOW}$1${RESET}"; }
err()  { echo -e "${RED}$1${RESET}"; }
info() { echo -e "${CYAN}$1${RESET}"; }

header() {
  clear
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "${WHITE}         INSTALADOR - PAINEL ADMIN JELLYFIN${RESET}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo
}

pause_enter() {
  echo
  read -rp "Pressione Enter para continuar..." _
}

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    err "Execute este instalador como root."
    exit 1
  fi
}

install_deps() {
  msg "Verificando dependências..."
  local need_update=0

  if ! command -v curl >/dev/null 2>&1; then
    warn "curl não encontrado."
    need_update=1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    warn "jq não encontrado."
    need_update=1
  fi

  if [ "$need_update" -eq 1 ]; then
    apt update
    apt install -y curl jq
  else
    msg "Dependências já instaladas."
  fi
}

download_files() {
  msg "Criando diretório base..."
  mkdir -p "$BASE_DIR"

  msg "Baixando arquivos do GitHub..."
  curl -fsSL "$REPO_URL/files/jf-expiry.sh" -o "$BASE_DIR/jf-expiry.sh"
  curl -fsSL "$REPO_URL/files/jellyfin-panel.sh" -o "$BASE_DIR/jellyfin-panel.sh"

  if [ ! -f "$BASE_DIR/usuarios.txt" ]; then
    curl -fsSL "$REPO_URL/files/usuarios.txt" -o "$BASE_DIR/usuarios.txt"
    msg "usuarios.txt criado."
  else
    warn "usuarios.txt já existe, mantendo arquivo atual."
  fi

  if [ ! -f "$BASE_DIR/config.env" ]; then
    curl -fsSL "$REPO_URL/files/config.env.example" -o "$BASE_DIR/config.env"
    msg "config.env criado a partir do exemplo."
  else
    warn "config.env já existe, mantendo arquivo atual."
  fi

  chmod +x "$BASE_DIR/jf-expiry.sh"
  chmod +x "$BASE_DIR/jellyfin-panel.sh"
}

configure_env() {
  echo
  info "Configuração do Jellyfin"
  echo "Digite 0 em qualquer campo para pular esta etapa."
  echo

  read -rp "Deseja configurar agora? [S/n]: " resp
  if [[ "$resp" =~ ^[Nn]$ ]]; then
    warn "Configuração pulada."
    return
  fi

  read -rp "URL do Jellyfin [http://127.0.0.1:8097](http://127.0.0.1:8097): " JF_URL_INPUT
  if [ "$JF_URL_INPUT" = "0" ]; then
    warn "Configuração pulada."
    return
  fi
  JF_URL_INPUT=${JF_URL_INPUT:-http://127.0.0.1:8097}

  read -rp "Usuário admin do Jellyfin [admin]: " JF_ADMIN_USER_INPUT
  if [ "$JF_ADMIN_USER_INPUT" = "0" ]; then
    warn "Configuração pulada."
    return
  fi
  JF_ADMIN_USER_INPUT=${JF_ADMIN_USER_INPUT:-admin}

  read -rsp "Senha admin do Jellyfin: " JF_ADMIN_PASS_INPUT
  echo
  if [ "$JF_ADMIN_PASS_INPUT" = "0" ]; then
    warn "Configuração pulada."
    return
  fi

  cat > "$BASE_DIR/config.env" <<EOF
JF_URL="$JF_URL_INPUT"
JF_ADMIN_USER="$JF_ADMIN_USER_INPUT"
JF_ADMIN_PASS="$JF_ADMIN_PASS_INPUT"
EOF

  msg "config.env atualizado com sucesso."
}

install_launcher() {
  msg "Criando comando global jellyfin..."
  cat > "$BIN_FILE" <<EOF
#!/bin/bash
$BASE_DIR/jellyfin-panel.sh
EOF
  chmod +x "$BIN_FILE"
}

install_cron() {
  echo
  read -rp "Deseja instalar verificação automática diária às 03:00? [S/n]: " addcron
  if [[ "$addcron" =~ ^[Nn]$ ]]; then
    warn "Cron não instalado."
    return
  fi

  if crontab -l 2>/dev/null | grep -Fq "$BASE_DIR/jf-expiry.sh verificar"; then
    warn "Cron já existe, nada foi alterado."
  else
    ( crontab -l 2>/dev/null; echo "$CRON_LINE" ) | crontab -
    msg "Cron instalado com sucesso."
  fi
}

test_auth() {
  echo
  read -rp "Deseja testar a autenticação agora? [S/n]: " testar
  if [[ "$testar" =~ ^[Nn]$ ]]; then
    warn "Teste de autenticação ignorado."
    return
  fi

  if "$BASE_DIR/jf-expiry.sh" testar-auth; then
    msg "Autenticação validada com sucesso."
  else
    err "Falha na autenticação."
    warn "Revise o arquivo: $BASE_DIR/config.env"
    warn "Resposta salva em: $BASE_DIR/last_auth_response.txt"
  fi
}

show_final() {
  echo
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo -e "${WHITE}Instalação concluída.${RESET}"
  echo -e "${CYAN}════════════════════════════════════════════════════════════${RESET}"
  echo
  echo -e "${GREEN}Arquivos instalados em:${RESET} $BASE_DIR"
  echo -e "${GREEN}Comando principal:${RESET} jellyfin"
  echo -e "${GREEN}Configuração:${RESET} $BASE_DIR/config.env"
  echo -e "${GREEN}Banco de usuários:${RESET} $BASE_DIR/usuarios.txt"
  echo -e "${GREEN}Log:${RESET} $BASE_DIR/expiry.log"
  echo
  echo -e "${YELLOW}Próximos passos:${RESET}"
  echo "1. Testar autenticação, se ainda não testou:"
  echo "   $BASE_DIR/jf-expiry.sh testar-auth"
  echo
  echo "2. Abrir o painel:"
  echo "   jellyfin"
  echo
}

main() {
  header
  need_root
  install_deps
  download_files
  configure_env
  install_launcher
  install_cron
  test_auth
  show_final
}

main
