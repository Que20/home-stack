#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"
INSTALL_DOCKER_SCRIPT="$ROOT_DIR/scripts/install-docker.sh"

resolve_host_ip() {
    local route_line ip

    route_line="$(ip -4 route get 1.1.1.1 2>/dev/null || true)"
    if [[ "$route_line" =~ src[[:space:]]([0-9.]+) ]]; then
        ip="${BASH_REMATCH[1]}"
        if [ -n "$ip" ]; then
            printf '%s\n' "$ip"
            return 0
        fi
    fi

    ip="$(hostname -I 2>/dev/null | cut -d' ' -f1)"
    if [ -n "$ip" ]; then
        printf '%s\n' "$ip"
        return 0
    fi

    return 1
}

normalize_host() {
    local value
    value="$1"

    value="${value#http://}"
    value="${value#https://}"
    value="${value%%/*}"

    printf '%s\n' "$value"
}

ask_input() {
    local title="$1"
    local prompt="$2"
    local default_value="$3"

    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "$title" --inputbox "$prompt" 10 80 "$default_value" 3>&1 1>&2 2>&3
        return
    fi

    read -r -p "$prompt [$default_value]: " input_value
    if [ -z "$input_value" ]; then
        printf '%s\n' "$default_value"
    else
        printf '%s\n' "$input_value"
    fi
}

ask_password() {
    local title="$1"
    local prompt="$2"

    if command -v whiptail >/dev/null 2>&1; then
        whiptail --title "$title" --passwordbox "$prompt" 10 80 3>&1 1>&2 2>&3
        return
    fi

    read -r -s -p "$prompt: " password_value
    printf '\n' >&2
    printf '%s\n' "$password_value"
}

bcrypt_hash_password() {
    local plain_password="$1"
    printf '%s\n' "$plain_password" | docker run --rm -i caddy:2 caddy hash-password
}

escape_dollars_for_env() {
    local value="$1"
    printf '%s\n' "${value//\$/\$\$}"
}

if [ ! -x "$INSTALL_DOCKER_SCRIPT" ]; then
    echo "Script introuvable ou non exécutable: $INSTALL_DOCKER_SCRIPT"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker n'est pas installé. Installation en cours..."
    "$INSTALL_DOCKER_SCRIPT"
fi

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker n'est toujours pas disponible après installation."
    exit 1
fi

detected_host="$(resolve_host_ip || true)"
if [ -z "$detected_host" ]; then
    detected_host="localhost"
fi

host_input="$(ask_input "Home Stack" "IP ou adresse de la machine" "$detected_host")"
host_value="$(normalize_host "$host_input")"

if [ -z "$host_value" ]; then
    echo "L'hôte ne peut pas être vide."
    exit 1
fi

auth_username="$(ask_input "Home Stack" "Username basic_auth (laisser vide pour désactiver)" "")"
auth_password=""
auth_hash=""
auth_hash_env=""

if [ -n "$auth_username" ]; then
    auth_password="$(ask_password "Home Stack" "Password basic_auth")"
fi

if [ -n "$auth_username" ] && [ -n "$auth_password" ]; then
    auth_hash="$(bcrypt_hash_password "$auth_password")"
    auth_hash_env="$(escape_dollars_for_env "$auth_hash")"
else
    auth_username=""
    auth_hash=""
    auth_hash_env=""
fi

: > "$ENV_FILE"
{
    printf 'GENERIC_TIMEZONE=Europe/Paris\n'
    printf 'POSTGRES_USER=admin\n'
    printf 'POSTGRES_PASSWORD=%s\n' "$(openssl rand -base64 24)"
    printf 'POSTGRES_DB=db\n'
    printf 'HOST_IP=%s\n' "$host_value"
    printf 'BASIC_AUTH_USERNAME=%s\n' "$auth_username"
    printf 'BASIC_AUTH_PASSWORD_HASH=%s\n' "$auth_hash_env"
} >> "$ENV_FILE"

echo ".env initialisé dans $ENV_FILE"
