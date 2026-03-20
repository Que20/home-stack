# Home Stack

Stack Docker pour monter rapidement un homelab sur Debian (Raspberry Pi, mini-PC, VM) avec un reverse proxy Caddy, un dashboard HTML simple et des services optionnels.

## Services disponibles

- `n8n`
- `gokapi`
- `metube`
- `bentopdf`
- `netdata`
- `glances`
- `postgres`
- `portainer`
- `caddy` (reverse proxy + page d'accueil)

## Captures d'ecran

![Dashboard](screenshot/dashboard.png)

<p align="center">
  <img src="screenshot/host_input.png" alt="Saisie de l'hote" width="32%" />
  <img src="screenshot/basic_auth_input.png" alt="Configuration basic auth" width="32%" />
  <img src="screenshot/services_select.png" alt="Selection des services" width="32%" />
</p>


## Structure du projet

```text
home-stack/
|-- .env.example
|-- config/
|   `-- caddy/
|       `-- Caddyfile
|-- compose/
|   |-- gokapi/
|   |   `-- compose.yml
|   |-- metube/
|   |   `-- compose.yml
|   |-- bentopdf/
|   |   `-- compose.yml
|   |-- n8n/
|   |   `-- compose.yml
|   |-- netdata/
|   |   `-- compose.yml
|   |-- glances/
|   |   `-- compose.yml
|   |-- postgres/
|   |   |-- compose.yml
|   |   `-- init.sql
|   `-- caddy/
|       `-- compose.yml
|-- html/
|   `-- index.html
|-- screenshot/
|   |-- basic_auth_input.png
|   |-- host_input.png
|   `-- services_select.png
`-- scripts/
    |-- backup.sh
    |-- init.sh
    |-- install.sh
    |-- install-docker.sh
    |-- restart.sh
    |-- restore.sh
    `-- stop.sh
```

## Prerequis

- OS Linux type Debian/Ubuntu
- `bash`
- `whiptail` (recommandé, fallback texte si absent)

Docker peut etre installe automatiquement par `scripts/init.sh` via `scripts/install-docker.sh`.

## Utilisation

1. Rendre les scripts executables:

```bash
chmod +x scripts/*.sh
```

2. Initialiser la configuration:

```bash
./scripts/init.sh
```

3. Installer et lancer les services choisis:

```bash
./scripts/install.sh
```

## Scripts utilitaires

- Redemarrer tous les conteneurs en cours:

```bash
./scripts/restart.sh
```

- Arrêter tous les conteneurs en cours:

```bash
./scripts/stop.sh
```

- Installer et configurer les paquet de sécurité: fail2ban, ufw et Unattended upgrades

```bash
./scripts/security.sh
```

## Backup et restore

- Sauvegarder les données `n8n`, `portainer` et `netdata`:

```bash
./scripts/backup.sh
```

Ce script crée des archives horodatées dans `backups/`:
- `backups/n8n_YYYYmmdd_HHMMSS.tar.gz`
- `backups/portainer_YYYYmmdd_HHMMSS.tar.gz`
- `backups/netdata_YYYYmmdd_HHMMSS.tar.gz`

- Réstaurer la derniere sauvegarde disponible de chaque service:

```bash
./scripts/restore.sh
```

- Restaurer une sauvegarde precise via timestamp:

```bash
./scripts/restore.sh 20260313_154500
```

Le script de restore stoppe temporairement les conteneurs concerns (`n8n`, `portainer`, `netdata`) puis les redémarre apres extraction.

## Variables `.env`

Valeurs gérées par `scripts/init.sh`:

- `HOST_IP`
- `BASIC_AUTH_USERNAME`
- `BASIC_AUTH_PASSWORD_HASH`

Valeurs applicatives (initialisées avec des defaults):

- `GENERIC_TIMEZONE`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_DB`

## Notes

- Les informations relatives à la config db sont à changer manuellement dans le .env.
- Le reseau Docker partage est `web`.
- Le fichier `config/caddy/Caddyfile` est généré automatiquement par `scripts/install.sh`.
- La page d'accueil est servie depuis `html/index.html`.
