#!/bin/bash

BASE_DIR="/opt/jellyfin-expiry"
SCRIPT="$BASE_DIR/jf-expiry.sh"
DB="$BASE_DIR/usuarios.txt"
LOG="$BASE_DIR/expiry.log"
CFG="$BASE_DIR/config.env"

R="\e[0m"
B="\e[1m"
RED="\e[1;31m"
GREEN="\e[1;32m"
YELLOW="\e[1;33m"
BLUE="\e[1;34m"
CYAN="\e[1;36m"
WHITE="\e[1;37m"
GRAY="\e[1;30m"

[ -x "$SCRIPT" ] || { echo "Script principal não encontrado: $SCRIPT"; exit 1; }
[ -f "$DB" ] || touch "$DB"

contar_status() {
    on_count=$(awk -F: '!/^#/ && $3=="on"{c++} END{print c+0}' "$DB")
    blocked_count=$(awk -F: '!/^#/ && $3=="blocked"{c++} END{print c+0}' "$DB")
    off_count=$(awk -F: '!/^#/ && $3=="off"{c++} END{print c+0}' "$DB")
    total_count=$(awk -F: '!/^#/ && NF>=2{c++} END{print c+0}' "$DB")
}

cabecalho() {
    contar_status
    clear
    echo -e "${CYAN}════════════════════════════════════════════════════════════${R}"
    echo -e "${WHITE}${B}                PAINEL JELLYFIN MANAGER${R}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${R}"
    echo -e "${GREEN}ON:${R} ${on_count}   ${RED}BLOCKED:${R} ${blocked_count}   ${YELLOW}OFF:${R} ${off_count}   ${BLUE}TOTAL:${R} ${total_count}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════${R}"
    echo
}

pausa() {
    echo
    read -rp "Pressione Enter para continuar..." _
}

mensagem_cancelado() {
    echo
    echo -e "${YELLOW}Operação cancelada. Voltando ao menu...${R}"
    sleep 1
}

input_cancelavel() {
    local prompt="$1"
    local var
    read -rp "$prompt" var
    if [ "$var" = "0" ]; then
        return 1
    fi
    REPLY_VALUE="$var"
    return 0
}

resolver_validade() {
    local entrada="$1"

    if [[ "$entrada" =~ ^[0-9]+$ ]]; then
        date -d "+$entrada days" +%F 2>/dev/null
        return
    fi

    if [[ "$entrada" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        date -d "$entrada" +%F 2>/dev/null
        return
    fi

    return 1
}

status_colorido() {
    local st="$1"
    case "$st" in
        on) echo -e "${GREEN}on${R}" ;;
        blocked) echo -e "${RED}blocked${R}" ;;
        off) echo -e "${YELLOW}off${R}" ;;
        *) echo -e "${WHITE}$st${R}" ;;
    esac
}

listar_formatado() {
    cabecalho
    echo -e "${WHITE}${B}Usuários em controle:${R}"
    echo
    if [ -s "$DB" ]; then
        printf "${CYAN}%-20s %-15s %-12s${R}\n" "USUARIO" "VALIDADE" "STATUS"
        echo -e "${GRAY}--------------------------------------------------${R}"
        awk -F: '!/^#/ && NF>=3 {print $1 ":" $2 ":" $3}' "$DB" | while IFS=: read -r u v s; do
            sc=$(status_colorido "$s")
            printf "%-20s %-15s " "$u" "$v"
            echo -e "$sc"
        done
    else
        echo -e "${YELLOW}Nenhum usuário cadastrado.${R}"
    fi
    pausa
}

ver_log() {
    cabecalho
    echo -e "${BLUE}${B}Últimos 30 registros:${R}"
    echo
    if [ -f "$LOG" ]; then
        tail -n 30 "$LOG" | while IFS= read -r linha; do
            if echo "$linha" | grep -q "DESATIVADO"; then
                echo -e "${RED}$linha${R}"
            elif echo "$linha" | grep -q "REATIVADO"; then
                echo -e "${GREEN}$linha${R}"
            elif echo "$linha" | grep -q "ERRO"; then
                echo -e "${YELLOW}$linha${R}"
            else
                echo -e "${WHITE}$linha${R}"
            fi
        done
    else
        echo -e "${YELLOW}Log vazio.${R}"
    fi
    pausa
}

verificar_agora() {
    cabecalho
    echo -e "${YELLOW}${B}Executando verificação de vencimentos...${R}"
    echo
    "$SCRIPT" verificar
    pausa
}

adicionar_controle() {
    cabecalho
    echo -e "${GREEN}${B}Adicionar usuário ao controle${R}"
    echo -e "${GRAY}Digite 0 em qualquer campo para voltar.${R}"
    echo

    input_cancelavel "Nome do usuário existente no Jellyfin: " || { mensagem_cancelado; return; }
    usuario="$REPLY_VALUE"

    input_cancelavel "Validade (dias ou AAAA-MM-DD): " || { mensagem_cancelado; return; }
    entrada="$REPLY_VALUE"

    validade=$(resolver_validade "$entrada")
    if [ -z "$validade" ]; then
        echo -e "${RED}Validade inválida. Use dias (ex: 30) ou data AAAA-MM-DD.${R}"
        pausa
        return
    fi

    echo
    echo -e "${CYAN}Data final calculada:${R} ${WHITE}$validade${R}"
    "$SCRIPT" adicionar "$usuario" "$validade"
    pausa
}

editar_validade() {
    cabecalho
    echo -e "${YELLOW}${B}Editar validade${R}"
    echo -e "${GRAY}Digite 0 em qualquer campo para voltar.${R}"
    echo

    input_cancelavel "Usuário: " || { mensagem_cancelado; return; }
    usuario="$REPLY_VALUE"

    input_cancelavel "Nova validade (dias ou AAAA-MM-DD): " || { mensagem_cancelado; return; }
    entrada="$REPLY_VALUE"

    validade=$(resolver_validade "$entrada")
    if [ -z "$validade" ]; then
        echo -e "${RED}Validade inválida. Use dias (ex: 30) ou data AAAA-MM-DD.${R}"
        pausa
        return
    fi

    echo
    echo -e "${CYAN}Nova data final:${R} ${WHITE}$validade${R}"
    "$SCRIPT" editar-data "$usuario" "$validade"
    pausa
}

reativar_usuario() {
    cabecalho
    echo -e "${GREEN}${B}Reativar usuário${R}"
    echo -e "${GRAY}Digite 0 para voltar.${R}"
    echo

    input_cancelavel "Usuário: " || { mensagem_cancelado; return; }
    usuario="$REPLY_VALUE"

    "$SCRIPT" reativar "$usuario"
    pausa
}

desativar_usuario() {
    cabecalho
    echo -e "${RED}${B}Desativar usuário${R}"
    echo -e "${GRAY}Digite 0 para voltar.${R}"
    echo

    input_cancelavel "Usuário: " || { mensagem_cancelado; return; }
    usuario="$REPLY_VALUE"

    "$SCRIPT" desativar "$usuario"
    pausa
}

pausar_controle() {
    cabecalho
    echo -e "${YELLOW}${B}Pausar controle automático${R}"
    echo -e "${GRAY}Digite 0 para voltar.${R}"
    echo

    input_cancelavel "Usuário: " || { mensagem_cancelado; return; }
    usuario="$REPLY_VALUE"

    "$SCRIPT" pausar "$usuario"
    pausa
}

ativar_controle() {
    cabecalho
    echo -e "${GREEN}${B}Ativar controle automático${R}"
    echo -e "${GRAY}Digite 0 para voltar.${R}"
    echo

    input_cancelavel "Usuário: " || { mensagem_cancelado; return; }
    usuario="$REPLY_VALUE"

    "$SCRIPT" ativar-controle "$usuario"
    pausa
}

remover_controle() {
    cabecalho
    echo -e "${RED}${B}Remover usuário do controle${R}"
    echo -e "${GRAY}Digite 0 para voltar.${R}"
    echo

    input_cancelavel "Usuário: " || { mensagem_cancelado; return; }
    usuario="$REPLY_VALUE"

    "$SCRIPT" remover "$usuario"
    pausa
}

ver_arquivo_bruto() {
    cabecalho
    echo -e "${WHITE}${B}Conteúdo bruto do usuarios.txt${R}"
    echo
    while IFS= read -r linha; do
        if [[ "$linha" =~ ^# ]]; then
            echo -e "${GRAY}$linha${R}"
        else
            echo -e "${WHITE}$linha${R}"
        fi
    done < "$DB"
    pausa
}

criar_usuario_jellyfin_manual() {
    cabecalho
    echo -e "${CYAN}${B}Criar usuário no Jellyfin + cadastrar no controle${R}"
    echo
    echo -e "${WHITE}Esta opção vai orientar a criação segura.${R}"
    echo -e "${WHITE}A criação final do usuário será feita no Dashboard do Jellyfin,${R}"
    echo -e "${WHITE}e o cadastro no controle será feito por este painel.${R}"
    echo
    echo -e "${GRAY}Digite 0 em qualquer campo para voltar.${R}"
    echo

    input_cancelavel "Nome do novo usuário: " || { mensagem_cancelado; return; }
    usuario="$REPLY_VALUE"

    input_cancelavel "Validade (dias ou AAAA-MM-DD): " || { mensagem_cancelado; return; }
    entrada="$REPLY_VALUE"

    validade=$(resolver_validade "$entrada")
    if [ -z "$validade" ]; then
        echo -e "${RED}Validade inválida. Use dias (ex: 30) ou data AAAA-MM-DD.${R}"
        pausa
        return
    fi

    echo
    echo -e "${CYAN}Data final calculada:${R} ${WHITE}$validade${R}"
    echo
    echo -e "${GREEN}1.${R} Abra o Jellyfin no navegador:"
    echo -e "   ${WHITE}https://jellyfin.maritimavpn.shop${R}"
    echo
    echo -e "${GREEN}2.${R} Vá em Dashboard > Users > +"
    echo
    echo -e "${GREEN}3.${R} Crie o usuário exatamente com este nome:"
    echo -e "   ${WHITE}$usuario${R}"
    echo
    read -rp "Depois que criar no Jellyfin, pressione Enter para continuar..." _

    "$SCRIPT" adicionar "$usuario" "$validade"
    echo
    echo -e "${GREEN}Usuário adicionado ao controle.${R}"
    pausa
}

status_rapido() {
    cabecalho
    echo -e "${WHITE}${B}Status rápido:${R}"
    echo
    echo -e "${CYAN}Comando principal:${R} jellyfin"
    echo -e "${CYAN}Banco:${R} $DB"
    echo -e "${CYAN}Log:${R} $LOG"
    echo -e "${CYAN}Script:${R} $SCRIPT"
    echo -e "${CYAN}Config:${R} $CFG"
    pausa
}

menu() {
    while true; do
        cabecalho
        echo -e "${WHITE}[1]${R}  Listar usuários"
        echo -e "${WHITE}[2]${R}  Verificar vencimentos agora"
        echo -e "${WHITE}[3]${R}  Adicionar usuário ao controle"
        echo -e "${WHITE}[4]${R}  Criar usuário Jellyfin + cadastrar"
        echo -e "${WHITE}[5]${R}  Editar validade"
        echo -e "${WHITE}[6]${R}  Reativar usuário"
        echo -e "${WHITE}[7]${R}  Desativar usuário"
        echo -e "${WHITE}[8]${R}  Pausar controle"
        echo -e "${WHITE}[9]${R}  Ativar controle"
        echo -e "${WHITE}[10]${R} Remover do controle"
        echo -e "${WHITE}[11]${R} Ver log"
        echo -e "${WHITE}[12]${R} Ver usuarios.txt bruto"
        echo -e "${WHITE}[13]${R} Status rápido"
        echo -e "${WHITE}[0]${R}  Sair"
        echo
        read -rp "Escolha uma opção: " op

        case "$op" in
            1) listar_formatado ;;
            2) verificar_agora ;;
            3) adicionar_controle ;;
            4) criar_usuario_jellyfin_manual ;;
            5) editar_validade ;;
            6) reativar_usuario ;;
            7) desativar_usuario ;;
            8) pausar_controle ;;
            9) ativar_controle ;;
            10) remover_controle ;;
            11) ver_log ;;
            12) ver_arquivo_bruto ;;
            13) status_rapido ;;
            0) clear; exit 0 ;;
            *) echo -e "${RED}Opção inválida.${R}"; sleep 1 ;;
        esac
    done
}

menu
