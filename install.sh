#!/bin/bash
set -e

REPO_URL="https://raw.githubusercontent.com/3rian/Painel-Admin-Jellyfin/main"
BASE_DIR="/opt/jellyfin-expiry"
BIN_FILE="/usr/local/bin/jellyfin"

red="\e[1;31m"
green="\e[1;32m"
yellow="\e[1;33m"
cyan="\e[1;36m"
reset="\e[0m"

msg()  { echo -e "${green}$1${reset}"; }
warn() { echo -e "${yellow}$1${reset}"; }
err()  { echo -e "${red}$1${reset}"; }

if [ "$(id -u)" -ne 0 ]; then
  err "Execute como root."
  exit 1
fi

msg "Criando diretório base..."
mkdir -p "$BASE_DIR"

msg "Verificando dependências..."
if ! command -v curl >/dev/null 2>&1; then
  apt update && apt install -y curl
fi

if ! command -v jq >/dev/null 2>&1; then
  apt update && apt install -y jq
fi

msg "Baixando arquivos do GitHub..."
curl -fsSL "$REPO_URL/files/jf-expiry.sh" -o "$BASE_DIR/jf-expiry.sh"
curl -fsSL "$REPO_URL/files/jellyfin-panel.sh" -o "$BASE_DIR/jellyfin-panel.sh"
curl -fsSL "$REPO_URL/files/usuarios.txt" -o "$BASE_DIR/usuarios.txt"

if [ ! -f "$BASE_DIR/config.env" ]; then
  curl -fsSL "$REPO_URL/files/config.env.example" -o "$BASE_DIR/config.env"
  warn "Arquivo config.env criado a partir do exemplo."
  warn "Edite $BASE_DIR/config.env antes de usar o painel."
else
  warn "config.env já existe, mantendo arquivo atual."
fi

msg "Aplicando permissões..."
chmod +x "$BASE_DIR/jf-expiry.sh"
chmod +x "$BASE_DIR/jellyfin-panel.sh"

msg "Criando launcher global..."
cat > "$BIN_FILE" <<EOF
#!/bin/bash
$BASE_DIR/jellyfin-panel.sh
EOF

chmod +x "$BIN_FILE"

if ! crontab -l 2>/dev/null | grep -q "$BASE_DIR/jf-expiry.sh verificar"; then
  warn "Instalando cron diário às 03:00..."
  ( crontab -l 2>/dev/null; echo "0 3 * * * $BASE_DIR/jf-expiry.sh verificar >/dev/null 2>&1" ) | crontab -
else
  warn "Cron já existente, mantendo como está."
fi

msg "Instalação concluída com sucesso."
echo
echo -e "${cyan}Próximos passos:${reset}"
echo "1. Edite o arquivo: $BASE_DIR/config.env"
echo "2. Teste autenticação: $BASE_DIR/jf-expiry.sh testar-auth"
echo "3. Abra o painel com: jellyfin"
