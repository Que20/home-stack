#!/usr/bin/env bash
set -euo pipefail

running_containers="$(docker ps -q)"

if [ -z "$running_containers" ]; then
    echo "Aucun conteneur en cours d'exécution."
    exit 0
fi

docker restart $(docker ps -q)
