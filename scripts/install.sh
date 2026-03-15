#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
CADDY_CONFIG_DIR="$ROOT_DIR/config/caddy"
CADDYFILE_PATH="$CADDY_CONFIG_DIR/Caddyfile"

get_env_value() {
    local key="$1"
    local line
    line="$(grep -E "^${key}=" "$ENV_FILE" | tail -n 1 || true)"
    if [ -z "$line" ]; then
        printf ''
        return
    fi
    printf '%s' "${line#*=}"
}

set_env_value() {
    local key="$1"
    local value="$2"
    local tmp_file
    local line
    local replaced=0

    tmp_file="$(mktemp)"

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" == "${key}="* ]]; then
            printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
            replaced=1
        else
            printf '%s\n' "$line" >> "$tmp_file"
        fi
    done < "$ENV_FILE"

    if [ "$replaced" -eq 0 ]; then
        printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
    fi

    mv "$tmp_file" "$ENV_FILE"
}

unescape_dollars_from_env() {
    local value="$1"
    printf '%s\n' "${value//\$\$/\$}"
}

normalize_basic_auth_hash_env() {
    local raw_hash
    local unescaped_hash
    local escaped_hash

    raw_hash="$(get_env_value BASIC_AUTH_PASSWORD_HASH)"
    if [ -z "$raw_hash" ]; then
        return
    fi

    unescaped_hash="$(unescape_dollars_from_env "$raw_hash")"
    escaped_hash="${unescaped_hash//\$/\$\$}"

    if [ "$raw_hash" != "$escaped_hash" ]; then
        set_env_value "BASIC_AUTH_PASSWORD_HASH" "$escaped_hash"
    fi
}

contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done
    return 1
}

choose_services_with_whiptail() {
    local current
    current="$(whiptail --title "Home Stack" --checklist "Sélectionne les services à installer" 20 90 10 \
    "n8n" "n8n" ON \
    "gokapi" "gokapi" ON \
    "metube" "metube" ON \
    "netdata" "netdat (netdata)" ON \
    "postgres" "postgres" ON \
    "portainer" "portainer" ON \
    3>&1 1>&2 2>&3)"

    current="${current//\"/}"
    read -r -a SELECTED <<< "$current"
}

choose_services_fallback() {
    echo "whiptail non disponible, passage en mode texte."
    echo "1) n8n"
    echo "2) gokapi"
    echo "3) metube"
    echo "4) netdata"
    echo "5) postgres"
    read -r -p "Entre les numéros séparés par des virgules (ex: 1,3,5): " choice

    SELECTED=()
    IFS=',' read -r -a picked <<< "$choice"

    local item
    for item in "${picked[@]}"; do
        case "${item// /}" in
            1) SELECTED+=("n8n") ;;
            2) SELECTED+=("gokapi") ;;
            3) SELECTED+=("metube") ;;
            4) SELECTED+=("netdata") ;;
            5) SELECTED+=("postgres") ;;
        esac
    done
}

generate_caddyfile() {
    local host="$1"
    local auth_username="$2"
    local auth_hash="$3"
    local timestamp

    mkdir -p "$CADDY_CONFIG_DIR"

    if [ -f "$CADDYFILE_PATH" ]; then
        timestamp="$(date +%Y%m%d_%H%M%S)"
        mv "$CADDYFILE_PATH" "${CADDYFILE_PATH}.${timestamp}"
    fi

    {
        printf '%s {\n' "$host"
        if [ -n "$auth_username" ] && [ -n "$auth_hash" ]; then
            printf '\tbasic_auth {\n'
            printf '\t\t%s %s\n' "$auth_username" "$auth_hash"
            printf '\t}\n\n'
        fi

        if contains "n8n" "${SELECTED[@]}"; then
            printf '\thandle_path /n8n/* {\n'
            printf '\t\treverse_proxy n8n:5678\n'
            printf '\t}\n\n'
        fi

        if contains "gokapi" "${SELECTED[@]}"; then
            printf '\thandle_path /gokapi/* {\n'
            printf '\t\treverse_proxy gokapi:53842\n'
            printf '\t}\n\n'
        fi

        if contains "metube" "${SELECTED[@]}"; then
            printf '\thandle_path /metube/* {\n'
            printf '\t\treverse_proxy metube:8081\n'
            printf '\t}\n\n'
        fi

        if contains "portainer" "${SELECTED[@]}"; then
            printf '\thandle_path /portainer/* {\n'
            printf '\t\treverse_proxy portainer:9000\n'
            printf '\t}\n\n'
        fi

        if contains "netdata" "${SELECTED[@]}"; then
            printf '\thandle_path /netdata/* {\n'
            printf '\t\treverse_proxy netdata:19999\n'
            printf '\t}\n\n'
        fi

        printf '\thandle {\n'
        printf '\t\troot * /srv\n'
        printf '\t\tfile_server\n'
        printf '\t}\n'
        printf '}\n'
    } > "$CADDYFILE_PATH"
}

if [ ! -f "$ENV_FILE" ]; then
    echo "Fichier .env introuvable. Lance d'abord scripts/init.sh"
    exit 1
fi

normalize_basic_auth_hash_env

HOST_IP="$(get_env_value HOST_IP)"
BASIC_AUTH_USERNAME="$(get_env_value BASIC_AUTH_USERNAME)"
BASIC_AUTH_PASSWORD_HASH="$(unescape_dollars_from_env "$(get_env_value BASIC_AUTH_PASSWORD_HASH)")"

if [ -z "${HOST_IP}" ]; then
    echo "HOST_IP est manquant dans .env"
    exit 1
fi

SELECTED=()
if command -v whiptail >/dev/null 2>&1; then
    choose_services_with_whiptail
else
    choose_services_fallback
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
    echo "Aucun service sélectionné."
    exit 0
fi

generate_caddyfile "$HOST_IP" "$BASIC_AUTH_USERNAME" "$BASIC_AUTH_PASSWORD_HASH"
echo "Caddyfile généré: $CADDYFILE_PATH"

docker network inspect web >/dev/null 2>&1 || docker network create web

for service in postgres n8n gokapi metube netdata portainer; do
    if contains "$service" "${SELECTED[@]}"; then
        echo "Déploiement ${service}"
        docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/compose/${service}/compose.yml" up -d
    fi
done

echo "Déploiement caddy"
docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/compose/caddy/compose.yml" up -d

echo "Installation terminée"
