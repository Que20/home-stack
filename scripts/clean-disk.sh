#!/usr/bin/env bash

set -Eeuo pipefail

JOURNAL_MAX_SIZE="${JOURNAL_MAX_SIZE:-100M}"
DOCKER_LOG_DIR="${DOCKER_LOG_DIR:-/var/lib/docker/containers}"

SUDO=()
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
  else
    echo "ERROR: This script needs root privileges for some steps and 'sudo' is not available."
    exit 1
  fi
fi

section() {
  echo "================================="
  echo "$1"
  echo "================================="
}

print_disk_usage() {
  df -h
  if command -v docker >/dev/null 2>&1; then
    echo
    docker system df || true
  fi
}

get_available_kb() {
  local available
  available="$(df -Pk / | awk 'NR==2 {print $4}')"
  if [[ "${available}" =~ ^[0-9]+$ ]]; then
    echo "${available}"
  else
    echo "0"
  fi
}

format_kb() {
  local kb="$1"
  local bytes=$((kb * 1024))

  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "${bytes}"
    return
  fi

  local gib=$((1024 * 1024))
  local mib=1024
  if (( kb >= gib )); then
    printf "%d GiB" $((kb / gib))
  elif (( kb >= mib )); then
    printf "%d MiB" $((kb / mib))
  else
    printf "%d KiB" "${kb}"
  fi
}

BEFORE_AVAILABLE_KB="$(get_available_kb)"

section "Disk usage BEFORE cleanup"
print_disk_usage
echo

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  section "Cleaning Docker"

  echo "Removing stopped containers..."
  docker container prune -f

  echo "Removing unused images..."
  docker image prune -af

  echo "Removing unused networks..."
  docker network prune -f

  echo "Removing build cache..."
  docker builder prune -af

  echo "Removing unused volumes..."
  docker volume prune -f

  echo

  section "Truncating large Docker logs"
  if [[ -d "${DOCKER_LOG_DIR}" ]]; then
    "${SUDO[@]}" find "${DOCKER_LOG_DIR}" -name "*-json.log" -type f -exec truncate -s 0 {} \;
  else
    echo "Docker log directory not found (${DOCKER_LOG_DIR}), skipping log truncation."
  fi

  echo

  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files docker.service >/dev/null 2>&1; then
    section "Restarting Docker (cleanup containerd snapshots)"
    "${SUDO[@]}" systemctl restart docker
    echo
  else
    section "Skipping Docker restart"
    echo "systemctl/docker.service not available on this host."
    echo
  fi
else
  section "Skipping Docker cleanup"
  echo "Docker is not installed or daemon is not running."
  echo
fi

if command -v apt-get >/dev/null 2>&1; then
  section "Cleaning apt cache"
  "${SUDO[@]}" apt-get clean
  "${SUDO[@]}" apt-get autoremove -y
  "${SUDO[@]}" rm -rf /var/lib/apt/lists/*
  echo
else
  section "Skipping apt cache cleanup"
  echo "apt-get is not available on this host."
  echo
fi

if command -v journalctl >/dev/null 2>&1; then
  section "Cleaning systemd journals"
  "${SUDO[@]}" journalctl --vacuum-size="${JOURNAL_MAX_SIZE}"
  echo
else
  section "Skipping journal cleanup"
  echo "journalctl is not available on this host."
  echo
fi

section "Disk usage AFTER cleanup"
print_disk_usage

AFTER_AVAILABLE_KB="$(get_available_kb)"
DELTA_KB=$((AFTER_AVAILABLE_KB - BEFORE_AVAILABLE_KB))

echo
section "Recovered space summary"
echo "Available before: $(format_kb "${BEFORE_AVAILABLE_KB}")"
echo "Available after : $(format_kb "${AFTER_AVAILABLE_KB}")"

if (( DELTA_KB > 0 )); then
  echo "Recovered       : $(format_kb "${DELTA_KB}")"
elif (( DELTA_KB < 0 )); then
  echo "Net change      : -$(format_kb "$((-DELTA_KB))") (less free space)"
else
  echo "Recovered       : 0 KiB"
fi

echo
echo "Cleanup completed."
