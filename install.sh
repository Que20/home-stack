#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    value="${value%%:*}"

    printf '%s\n' "$value"
}

ensure_env_file() {
    if [ -f "$ROOT_DIR/.env" ]; then
        return 0
    fi

    if [ -f "$ROOT_DIR/.env.example" ]; then
        echo "==> .env introuvable, copie depuis .env.example"
        cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
    else
        echo "==> .env introuvable, création d'un template minimal"
        cat > "$ROOT_DIR/.env" <<'EOF'
GENERIC_TIMEZONE=Europe/Paris
POSTGRES_USER=postgres
POSTGRES_PASSWORD=change_me
POSTGRES_DB=n8n
EOF
    fi

    echo ""
    echo "Edite $ROOT_DIR/.env puis relance le script."
    return 1
}

install_docker_engine() {
    echo "==> Mise à jour système"
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg

    echo "==> Ajout de la clé GPG Docker"
    sudo install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.asc ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
        sudo chmod a+r /etc/apt/keyrings/docker.asc
    fi

    echo "==> Ajout du dépôt Docker"
    ARCH="$(dpkg --print-architecture)"
    CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"

    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian ${CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    echo "==> Installation Docker Engine + Compose plugin"
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    echo "==> Activation du service Docker"
    sudo systemctl enable docker
    sudo systemctl start docker

    echo "==> Ajout de l'utilisateur courant au groupe docker"
    if ! groups "$USER" | grep -q '\bdocker\b'; then
        sudo usermod -aG docker "$USER"
        echo "Utilisateur ajouté au groupe docker. Reconnecte-toi ou lance 'newgrp docker'."
    fi

    echo "==> Vérifications Docker"
    docker --version
    docker compose version
}

choose_services_with_whiptail() {
    local current
    current="$(whiptail --title "Home Stack" --checklist "Selectionne les services a configurer et demarrer" 20 90 10 \
    "postgres" "PostgreSQL" ON \
    "n8n" "n8n" ON \
    "gokapi" "Gokapi (temp file sharing)" ON \
    "netdata" "Netdata" ON \
    "nginx" "Nginx reverse proxy" ON \
    "portainer" "Portainer" ON \
    3>&1 1>&2 2>&3)"

    current="${current//\"/}"
    read -r -a SELECTED <<< "$current"
}

choose_services_fallback() {
    echo "whiptail non disponible, passage en mode texte."
    echo ""
    echo "Services disponibles:"
    echo "0) tout"
    echo "1) postgres"
    echo "2) n8n"
    echo "3) gokapi"
    echo "4) netdata"
    echo "5) nginx"
    echo "6) portainer"
    echo ""
    read -r -p "Entre les numeros separes par des virgules (ex: 0 ou 1,2,5): " choice

    SELECTED=()
    IFS=',' read -r -a picked <<< "$choice"

    local normalized
    normalized="${choice// /}"
    if [[ "$normalized" == *"0"* ]]; then
        SELECTED=("postgres" "n8n" "gokapi" "netdata" "nginx" "portainer")
        return
    fi

    local item
    for item in "${picked[@]}"; do
        case "${item// /}" in
            1) SELECTED+=("postgres") ;;
            2) SELECTED+=("n8n") ;;
            3) SELECTED+=("gokapi") ;;
            4) SELECTED+=("netdata") ;;
            5) SELECTED+=("nginx") ;;
            6) SELECTED+=("portainer") ;;
        esac
    done
}

ask_host_with_whiptail() {
    local default_host input

    default_host="$1"
    input="$(whiptail --title "Home Stack" --inputbox "URL/IP du serveur (sera utilisee pour HOST_IP)" 10 90 "$default_host" 3>&1 1>&2 2>&3)" || {
        echo "Operation annulee."
        exit 0
    }

    HOST_IP="$(normalize_host "$input")"
}

ask_host_fallback() {
    local default_host input

    default_host="$1"
    read -r -p "URL/IP du serveur [${default_host}]: " input

    if [ -z "$input" ]; then
        input="$default_host"
    fi

    HOST_IP="$(normalize_host "$input")"
}

SELECTED=()
USE_WHIPTAIL=0
if command -v whiptail > /dev/null 2>&1; then
    USE_WHIPTAIL=1
    choose_services_with_whiptail
else
    choose_services_fallback
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
    echo "Aucun service sélectionné."
    exit 0
fi

if ! command -v docker > /dev/null 2>&1; then
    echo "==> Docker est requis, installation automatique"
    install_docker_engine
fi

if ! command -v docker > /dev/null 2>&1; then
    echo "Docker n'est pas disponible. Abandon."
    exit 1
fi

if ! ensure_env_file; then
    exit 0
fi

HOST_IP="$(resolve_host_ip || true)"
if [ -z "$HOST_IP" ]; then
    echo "Impossible de detecter automatiquement l'IP locale."
    exit 1
fi

if [ "$USE_WHIPTAIL" -eq 1 ]; then
    ask_host_with_whiptail "$HOST_IP"
else
    ask_host_fallback "$HOST_IP"
fi

if [ -z "$HOST_IP" ]; then
    echo "HOST_IP vide. Abandon."
    exit 1
fi

export HOST_IP
echo "==> HOST_IP retenu: ${HOST_IP}"

if contains "n8n" "${SELECTED[@]}" && ! contains "nginx" "${SELECTED[@]}"; then
    echo "WARNING: n8n est deploye sans nginx, l'interface ne sera pas exposee en HTTP standard."
fi
if contains "portainer" "${SELECTED[@]}" && ! contains "nginx" "${SELECTED[@]}"; then
    echo "WARNING: portainer est deploye sans nginx, il ne sera pas expose sans mapping de port supplementaire."
fi

echo "==> Création du réseau Docker partagé"
docker network inspect web > /dev/null 2>&1 || docker network create web

for service in postgres n8n gokapi netdata; do
    if contains "$service" "${SELECTED[@]}"; then
        echo "==> Déploiement ${service}"
        docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/${service}/compose.yml" up -d
    fi
done

RP_SERVICES=()
if contains "nginx" "${SELECTED[@]}"; then
    RP_SERVICES+=("nginx")
fi
if contains "portainer" "${SELECTED[@]}"; then
    RP_SERVICES+=("portainer")
fi

if [ ${#RP_SERVICES[@]} -gt 0 ]; then
    echo "==> Déploiement reverse-proxy (${RP_SERVICES[*]})"
    docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/reverse-proxy/compose.yml" up -d "${RP_SERVICES[@]}"
fi

echo ""
echo "==> Déploiement terminé"
if contains "nginx" "${SELECTED[@]}"; then
    echo "Homepage:   http://${HOST_IP}/"
fi
if contains "n8n" "${SELECTED[@]}" && contains "nginx" "${SELECTED[@]}"; then
    echo "n8n:        http://${HOST_IP}/n8n/"
fi
if contains "gokapi" "${SELECTED[@]}"; then
    if contains "nginx" "${SELECTED[@]}"; then
        echo "gokapi (proxy): http://${HOST_IP}/gokapi/"
    fi
    echo "gokapi:      http://${HOST_IP}:53842/ for config: http://${HOST_IP}/gokapi/setup"
fi
if contains "netdata" "${SELECTED[@]}"; then
    if contains "nginx" "${SELECTED[@]}"; then
        echo "netdata:    http://${HOST_IP}/netdata/"
    fi
    echo "netdata:    http://${HOST_IP}:19999/"
fi
if contains "portainer" "${SELECTED[@]}" && contains "nginx" "${SELECTED[@]}"; then
    echo "portainer:  http://${HOST_IP}/portainer/"
fi
