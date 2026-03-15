#!/bin/bash

BASE_DIR="/opt/jellyfin-expiry"
CONFIG="$BASE_DIR/config.env"
USERS_DB="$BASE_DIR/usuarios.txt"
LOG="$BASE_DIR/expiry.log"

[ -f "$CONFIG" ] || { echo "Config não encontrada"; exit 1; }
[ -f "$USERS_DB" ] || { echo "usuarios.txt não encontrado"; exit 1; }

source "$CONFIG"

AUTH_HEADER='MediaBrowser Client="MaritimaExpiry", Device="Ubuntu", DeviceId="maritima-jellyfin-expiry", Version="1.0.0"'

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

show_help() {
  cat <<EOF2
Uso:
  $0 adicionar USUARIO AAAA-MM-DD
  $0 remover USUARIO
  $0 listar
  $0 verificar
  $0 reativar USUARIO
  $0 desativar USUARIO
  $0 editar-data USUARIO AAAA-MM-DD
  $0 pausar USUARIO
  $0 ativar-controle USUARIO
  $0 testar-auth
EOF2
}

get_token() {
  local resp
  resp=$(curl -s \
    -H 'Content-Type: application/json' \
    -H 'X-Emby-Authorization: MediaBrowser Client="MaritimaExpiry", Device="Ubuntu", DeviceId="maritima-jellyfin-expiry", Version="1.0.0"' \
    -X POST "$JF_URL/Users/AuthenticateByName" \
    -d "{\"Username\":\"$JF_ADMIN_USER\",\"Pw\":\"$JF_ADMIN_PASS\"}")

  echo "$resp" > "$BASE_DIR/last_auth_response.txt"
  echo "$resp" | jq -r '.AccessToken' 2>/dev/null
}

api_get() {
  local endpoint="$1"
  curl -s \
    -H "X-Emby-Authorization: $AUTH_HEADER, Token=\"$TOKEN\"" \
    "$JF_URL$endpoint"
}

api_post_json() {
  local endpoint="$1"
  local payload="$2"
  curl -s -o /dev/null -w "%{http_code}" \
    -H "Content-Type: application/json" \
    -H "X-Emby-Authorization: $AUTH_HEADER, Token=\"$TOKEN\"" \
    -X POST "$JF_URL$endpoint" \
    -d "$payload"
}

require_auth() {
  TOKEN="$(get_token)"
  if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    log "ERRO: falha ao autenticar no Jellyfin"
    log "Veja: $BASE_DIR/last_auth_response.txt"
    exit 1
  fi
  USERS_JSON="$(api_get "/Users")"
}

find_user_id() {
  local username="$1"
  echo "$USERS_JSON" | jq -r --arg u "$username" '.[] | select(.Name==$u) | .Id' | head -n1
}

set_disabled() {
  local user_id="$1"
  local disabled="$2"

  local user_json policy_json payload code

  user_json="$(api_get "/Users/$user_id")"
  policy_json="$(echo "$user_json" | jq '.Policy')"
  payload="$(echo "$policy_json" | jq --argjson v "$disabled" '.IsDisabled = $v')"

  code="$(api_post_json "/Users/$user_id/Policy" "$payload")"

  if [ "$code" = "204" ] || [ "$code" = "200" ]; then
    return 0
  fi
  return 1
}

set_status_db() {
  local username="$1"
  local new_status="$2"
  awk -F: -v u="$username" -v s="$new_status" '
    BEGIN{OFS=":"}
    $1==u {$3=s}
    {print}
  ' "$USERS_DB" > "$USERS_DB.tmp" && mv "$USERS_DB.tmp" "$USERS_DB"
}

set_date_db() {
  local username="$1"
  local new_date="$2"
  awk -F: -v u="$username" -v d="$new_date" '
    BEGIN{OFS=":"}
    $1==u {$2=d}
    {print}
  ' "$USERS_DB" > "$USERS_DB.tmp" && mv "$USERS_DB.tmp" "$USERS_DB"
}

user_exists_db() {
  local username="$1"
  grep -q "^$username:" "$USERS_DB"
}

expire_if_needed() {
  local username="$1"
  local validade="$2"
  local status="$3"
  local user_id="$4"

  local hoje user_json is_disabled

  hoje="$(date +%F)"
  user_json="$(api_get "/Users/$user_id")"
  is_disabled="$(echo "$user_json" | jq -r '.Policy.IsDisabled')"

  if [[ "$validade" < "$hoje" || "$validade" == "$hoje" ]]; then
    if [ "$is_disabled" != "true" ]; then
      if set_disabled "$user_id" true; then
        set_status_db "$username" "blocked"
        log "DESATIVADO: $username (venceu em $validade)"
      else
        log "ERRO ao desativar: $username"
      fi
    else
      set_status_db "$username" "blocked"
      log "JÁ BLOQUEADO: $username"
    fi
  else
    log "OK: $username válido até $validade (status $status)"
  fi
}

cmd="$1"

case "$cmd" in
  adicionar)
    usuario="$2"
    validade="$3"

    if [ -z "$usuario" ] || [ -z "$validade" ]; then
      show_help
      exit 1
    fi

    if ! [[ "$validade" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      echo "Data inválida. Use AAAA-MM-DD"
      exit 1
    fi

    if user_exists_db "$usuario"; then
      echo "Usuário já existe no usuarios.txt"
      exit 1
    fi

    echo "$usuario:$validade:on" >> "$USERS_DB"
    echo "Adicionado: $usuario -> $validade"
    exit 0
    ;;
  remover)
    usuario="$2"
    [ -z "$usuario" ] && { show_help; exit 1; }
    sed -i "/^$usuario:/d" "$USERS_DB"
    echo "Removido do controle: $usuario"
    exit 0
    ;;
  listar)
    echo "=== usuarios.txt ==="
    column -t -s: "$USERS_DB" 2>/dev/null || cat "$USERS_DB"
    exit 0
    ;;
  editar-data)
    usuario="$2"
    validade="$3"
    [ -z "$usuario" ] || [ -z "$validade" ] && { show_help; exit 1; }

    if ! user_exists_db "$usuario"; then
      echo "Usuário não encontrado no usuarios.txt"
      exit 1
    fi

    if ! [[ "$validade" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
      echo "Data inválida. Use AAAA-MM-DD"
      exit 1
    fi

    set_date_db "$usuario" "$validade"
    echo "Validade alterada: $usuario -> $validade"
    exit 0
    ;;
  pausar)
    usuario="$2"
    [ -z "$usuario" ] && { show_help; exit 1; }

    if ! user_exists_db "$usuario"; then
      echo "Usuário não encontrado no usuarios.txt"
      exit 1
    fi

    set_status_db "$usuario" "off"
    echo "Controle pausado para: $usuario"
    exit 0
    ;;
  ativar-controle)
    usuario="$2"
    [ -z "$usuario" ] && { show_help; exit 1; }

    if ! user_exists_db "$usuario"; then
      echo "Usuário não encontrado no usuarios.txt"
      exit 1
    fi

    set_status_db "$usuario" "on"
    echo "Controle ativado para: $usuario"
    exit 0
    ;;
  testar-auth)
    TOKEN="$(get_token)"
    if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then
      echo "Autenticação OK"
      exit 0
    else
      echo "Falha na autenticação"
      echo "Veja: $BASE_DIR/last_auth_response.txt"
      exit 1
    fi
    ;;
esac

require_auth

case "$cmd" in
  verificar)
    while IFS=: read -r usuario validade status; do
      [ -z "$usuario" ] && continue
      [[ "$usuario" =~ ^# ]] && continue
      [ -z "$status" ] && status="on"

      if [ "$status" = "off" ]; then
        log "IGNORADO: $usuario (status off)"
        continue
      fi

      if ! [[ "$validade" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        log "IGNORADO: validade inválida para $usuario -> $validade"
        continue
      fi

      user_id="$(find_user_id "$usuario")"
      if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
        log "NÃO ENCONTRADO no Jellyfin: $usuario"
        continue
      fi

      expire_if_needed "$usuario" "$validade" "$status" "$user_id"
    done < "$USERS_DB"
    ;;
  reativar)
    usuario="$2"
    [ -z "$usuario" ] && { show_help; exit 1; }

    if ! user_exists_db "$usuario"; then
      echo "Usuário não encontrado no usuarios.txt"
      exit 1
    fi

    user_id="$(find_user_id "$usuario")"
    [ -z "$user_id" ] || [ "$user_id" = "null" ] && { echo "Usuário não encontrado no Jellyfin"; exit 1; }

    if set_disabled "$user_id" false; then
      set_status_db "$usuario" "on"
      echo "Usuário reativado: $usuario"
      log "REATIVADO MANUALMENTE: $usuario"
    else
      echo "Erro ao reativar: $usuario"
      exit 1
    fi
    ;;
  desativar)
    usuario="$2"
    [ -z "$usuario" ] && { show_help; exit 1; }

    if ! user_exists_db "$usuario"; then
      echo "Usuário não encontrado no usuarios.txt"
      exit 1
    fi

    user_id="$(find_user_id "$usuario")"
    [ -z "$user_id" ] || [ "$user_id" = "null" ] && { echo "Usuário não encontrado no Jellyfin"; exit 1; }

    if set_disabled "$user_id" true; then
      set_status_db "$usuario" "blocked"
      echo "Usuário desativado: $usuario"
      log "DESATIVADO MANUALMENTE: $usuario"
    else
      echo "Erro ao desativar: $usuario"
      exit 1
    fi
    ;;
  *)
    show_help
    exit 1
    ;;
esac
