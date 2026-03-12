#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

if [ ! -f "$ROOT_DIR/.env" ]; then
    echo "Fichier .env introuvable."
    echo "Lance d'abord ./install.sh pour le generer."
    exit 1
fi

HOST_IP="$(resolve_host_ip || true)"
if [ -z "$HOST_IP" ]; then
    echo "Impossible de detecter automatiquement l'IP locale."
    exit 1
fi
export HOST_IP

docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/postgres/compose.yml" pull || true
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/n8n/compose.yml" pull
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/gokapi/compose.yml" pull
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/netdata/compose.yml" pull
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/reverse-proxy/compose.yml" pull

docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/postgres/compose.yml" up -d
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/n8n/compose.yml" up -d
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/gokapi/compose.yml" up -d
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/netdata/compose.yml" up -d
docker compose --env-file "$ROOT_DIR/.env" -f "$ROOT_DIR/compose/reverse-proxy/compose.yml" up -d
