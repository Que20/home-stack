#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
REQUESTED_TIMESTAMP="${1:-}"

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

get_archive_for_service() {
    local service_name="$1"
    local archive

    if [ -n "$REQUESTED_TIMESTAMP" ]; then
        archive="${BACKUP_DIR}/${service_name}_${REQUESTED_TIMESTAMP}.tar.gz"
        if [ -f "$archive" ]; then
            printf '%s\n' "$archive"
            return
        fi
        printf ''
        return
    fi

    archive="$(ls -1t "${BACKUP_DIR}/${service_name}_"*.tar.gz 2>/dev/null | head -n 1 || true)"
    printf '%s\n' "$archive"
}

is_container_running() {
    local container_name="$1"
    if docker ps --format '{{.Names}}' | grep -Fx "$container_name" >/dev/null 2>&1; then
        printf '1\n'
    else
        printf '0\n'
    fi
}

restore_volume() {
    local service_name="$1"
    local container_name="$2"
    local volume_name="$3"
    local archive_path="$4"
    local was_running

    if [ -z "$volume_name" ]; then
        echo "[WARN] Volume introuvable pour ${service_name}, restore ignore."
        return
    fi

    if [ -z "$archive_path" ] || [ ! -f "$archive_path" ]; then
        echo "[WARN] Archive introuvable pour ${service_name}, restore ignore."
        return
    fi

    was_running="$(is_container_running "$container_name")"
    if [ "$was_running" = "1" ]; then
        echo "Arret du conteneur ${container_name}"
        docker stop "$container_name" >/dev/null
    fi

    echo "Restauration ${service_name} depuis $(basename "$archive_path")"
    docker run --rm \
        -v "${volume_name}:/target" \
        alpine:3.20 \
        sh -c "rm -rf /target/* /target/.[!.]* /target/..?*"

    docker run --rm \
        -v "${volume_name}:/target" \
        -v "${BACKUP_DIR}:/backup:ro" \
        alpine:3.20 \
        sh -c "tar xzf /backup/$(basename "$archive_path") -C /target"

    if [ "$was_running" = "1" ]; then
        echo "Redemarrage du conteneur ${container_name}"
        docker start "$container_name" >/dev/null
    fi
}

restore_netdata_volumes() {
    local config_volume="$1"
    local lib_volume="$2"
    local cache_volume="$3"
    local archive_path="$4"
    local was_running

    if [ -z "$config_volume" ] || [ -z "$lib_volume" ] || [ -z "$cache_volume" ]; then
        echo "[WARN] Volumes Netdata incomplets, restore ignore."
        return
    fi

    if [ -z "$archive_path" ] || [ ! -f "$archive_path" ]; then
        echo "[WARN] Archive introuvable pour netdata, restore ignore."
        return
    fi

    was_running="$(is_container_running "netdata")"
    if [ "$was_running" = "1" ]; then
        echo "Arret du conteneur netdata"
        docker stop "netdata" >/dev/null
    fi

    echo "Restauration netdata depuis $(basename "$archive_path")"
    docker run --rm \
        -v "${config_volume}:/target/config" \
        -v "${lib_volume}:/target/lib" \
        -v "${cache_volume}:/target/cache" \
        alpine:3.20 \
        sh -c "rm -rf /target/config/* /target/config/.[!.]* /target/config/..?* /target/lib/* /target/lib/.[!.]* /target/lib/..?* /target/cache/* /target/cache/.[!.]* /target/cache/..?*"

    docker run --rm \
        -v "${config_volume}:/target/config" \
        -v "${lib_volume}:/target/lib" \
        -v "${cache_volume}:/target/cache" \
        -v "${BACKUP_DIR}:/backup:ro" \
        alpine:3.20 \
        sh -c "tar xzf /backup/$(basename "$archive_path") -C /target"

    if [ "$was_running" = "1" ]; then
        echo "Redemarrage du conteneur netdata"
        docker start "netdata" >/dev/null
    fi
}

if [ ! -d "$BACKUP_DIR" ]; then
    echo "Repertoire de backup introuvable: $BACKUP_DIR"
    exit 1
fi

n8n_volume="$(resolve_n8n_volume)"
portainer_volume="$(resolve_portainer_volume)"
netdata_config_volume="$(resolve_netdata_config_volume)"
netdata_lib_volume="$(resolve_netdata_lib_volume)"
netdata_cache_volume="$(resolve_netdata_cache_volume)"

n8n_archive="$(get_archive_for_service "n8n")"
portainer_archive="$(get_archive_for_service "portainer")"
netdata_archive="$(get_archive_for_service "netdata")"

restore_volume "n8n" "n8n" "$n8n_volume" "$n8n_archive"
restore_volume "portainer" "portainer" "$portainer_volume" "$portainer_archive"
restore_netdata_volumes "$netdata_config_volume" "$netdata_lib_volume" "$netdata_cache_volume" "$netdata_archive"

echo "Restore termine."
