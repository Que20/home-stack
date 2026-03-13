#!/usr/bin/env bash
set -euo pipefail

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
