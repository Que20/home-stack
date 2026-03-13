#!/usr/bin/env bash
set -euo pipefail

# =========================
# Configuration
# =========================
SSH_PORT="22"
SSH_MAXRETRY="5"
SSH_BANTIME="1h"

# Ouvre HTTP/HTTPS si tu en as besoin
ALLOW_HTTP="yes"
ALLOW_HTTPS="yes"

# =========================
# Vérifications
# =========================
if [[ "${EUID}" -ne 0 ]]; then
	echo "Ce script doit être lancé en root."
	echo "Exemple : sudo bash secure-server.sh"
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive

echo "Mise à jour de l'index APT"
apt-get update

echo "Installation des paquets"
apt-get install -y fail2ban ufw unattended-upgrades

# =========================
# Fail2Ban
# =========================
echo "Configuration de Fail2Ban"
mkdir -p /etc/fail2ban

cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime = ${SSH_BANTIME}
findtime = 10m
maxretry = ${SSH_MAXRETRY}
backend = systemd

[sshd]
enabled = true
port = ${SSH_PORT}
logpath = %(sshd_log)s
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# =========================
# UFW
# =========================
echo "Configuration de UFW"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}"/tcp comment 'SSH'

if [[ "${ALLOW_HTTP}" == "yes" ]]; then
	ufw allow 80/tcp comment 'HTTP'
fi

if [[ "${ALLOW_HTTPS}" == "yes" ]]; then
	ufw allow 443/tcp comment 'HTTPS'
fi

ufw --force enable

# =========================
# Unattended upgrades
# =========================
echo "Configuration de unattended-upgrades"
cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# On garde le fichier standard du paquet et on active le service
systemctl enable unattended-upgrades
systemctl restart unattended-upgrades

# =========================
# Résumé
# =========================
echo
echo "Configuration terminée"
echo
echo "--- UFW ---"
ufw status verbose || true
echo
echo "--- Fail2Ban ---"
fail2ban-client status sshd || true
echo
echo "--- Unattended upgrades ---"
systemctl --no-pager --full status unattended-upgrades || true