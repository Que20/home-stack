#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"

get_container_volume() {
    local container_name="$1"
    local destination="$2"
    local line volume mount_dest

    if docker inspect "$container_name" >/dev/null 2>&1; then
        while IFS= read -r line; do
            volume="${line%% *}"
            mount_dest="${line#* }"
            if [ "$mount_dest" = "$destination" ]; then
                printf '%s\n' "$volume"
                return
            fi
        done < <(docker inspect -f '{{ range .Mounts }}{{ if eq .Type "volume" }}{{ .Name }} {{ .Destination }}{{ println }}{{ end }}{{ end }}' "$container_name")
        return
    fi

    printf ''
}

find_volume_by_suffix() {
    local suffix="$1"
    docker volume ls --format '{{.Name}}' | grep -E "(^|[-_])${suffix}$" | head -n 1 || true
}

resolve_n8n_volume() {
    local vol
    vol="$(get_container_volume "n8n" "/home/node/.n8n")"
    if [ -n "$vol" ]; then
        printf '%s\n' "$vol"
        return
    fi
    find_volume_by_suffix "n8n_data"
}

resolve_portainer_volume() {
    local vol
    vol="$(get_container_volume "portainer" "/data")"
    if [ -n "$vol" ]; then
        printf '%s\n' "$vol"
        return
    fi
    find_volume_by_suffix "portainer_data"
}

resolve_netdata_config_volume() {
    local vol
    vol="$(get_container_volume "netdata" "/etc/netdata")"
    if [ -n "$vol" ]; then
        printf '%s\n' "$vol"
        return
    fi
    find_volume_by_suffix "netdataconfig"
}

resolve_netdata_lib_volume() {
    local vol
    vol="$(get_container_volume "netdata" "/var/lib/netdata")"
    if [ -n "$vol" ]; then
        printf '%s\n' "$vol"
        return
    fi
    find_volume_by_suffix "netdatalib"
}

resolve_netdata_cache_volume() {
    local vol
    vol="$(get_container_volume "netdata" "/var/cache/netdata")"
    if [ -n "$vol" ]; then
        printf '%s\n' "$vol"
        return
    fi
    find_volume_by_suffix "netdatacache"
}

backup_volume() {
    local service_name="$1"
    local volume_name="$2"
    local archive_name="${service_name}_${TIMESTAMP}.tar.gz"

    if [ -z "$volume_name" ]; then
        echo "[WARN] Volume introuvable pour ${service_name}, backup ignore."
        return
    fi

    echo "Backup ${service_name} depuis volume ${volume_name}"
    docker run --rm \
        -v "${volume_name}:/source:ro" \
        -v "${BACKUP_DIR}:/backup" \
        alpine:3.20 \
        sh -c "tar czf /backup/${archive_name} -C /source ."

    echo "Archive creee: ${BACKUP_DIR}/${archive_name}"
}

backup_netdata_volumes() {
    local config_volume="$1"
    local lib_volume="$2"
    local cache_volume="$3"
    local archive_name="netdata_${TIMESTAMP}.tar.gz"

    if [ -z "$config_volume" ] || [ -z "$lib_volume" ] || [ -z "$cache_volume" ]; then
        echo "[WARN] Volumes Netdata incomplets, backup ignore."
        return
    fi

    echo "Backup netdata depuis volumes ${config_volume}, ${lib_volume}, ${cache_volume}"
    docker run --rm \
        -v "${config_volume}:/source/config:ro" \
        -v "${lib_volume}:/source/lib:ro" \
        -v "${cache_volume}:/source/cache:ro" \
        -v "${BACKUP_DIR}:/backup" \
        alpine:3.20 \
        sh -c "tar czf /backup/${archive_name} -C /source config lib cache"

    echo "Archive creee: ${BACKUP_DIR}/${archive_name}"
}

mkdir -p "$BACKUP_DIR"

n8n_volume="$(resolve_n8n_volume)"
portainer_volume="$(resolve_portainer_volume)"
netdata_config_volume="$(resolve_netdata_config_volume)"
netdata_lib_volume="$(resolve_netdata_lib_volume)"
netdata_cache_volume="$(resolve_netdata_cache_volume)"

backup_volume "n8n" "$n8n_volume"
backup_volume "portainer" "$portainer_volume"
backup_netdata_volumes "$netdata_config_volume" "$netdata_lib_volume" "$netdata_cache_volume"

echo "Backup termine."
