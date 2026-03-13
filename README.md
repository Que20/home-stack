# Home Stack

Stack Docker pour monter rapidement un homelab sur Debian (Raspberry Pi, mini-PC, VM) avec un reverse proxy Caddy, un dashboard HTML simple et des services optionnels.

## Services disponibles

- `n8n`
- `gokapi`
- `netdata`
- `postgres`
- `caddy` (reverse proxy + page d'accueil)

## Captures d'ecran

### Saisie de l'hote

![Saisie de l'hote](screenshot/host_input.png)

### Configuration basic auth

![Configuration basic auth](screenshot/basic_auth_input.png)

### Selection des services

![Selection des services](screenshot/services_select.png)

## Structure du projet

```text
home-stack/
|-- .env.example
|-- compose/
|   |-- gokapi/
|   |   `-- compose.yml
|   |-- n8n/
|   |   `-- compose.yml
|   |-- netdata/
|   |   `-- compose.yml
|   |-- postgres/
|   |   |-- compose.yml
|   |   `-- init.sql
|   `-- reverse-proxy/
|       |-- Caddyfile
|       `-- compose.yml
|-- html/
|   `-- index.html
|-- screenshot/
|   |-- basic_auth_input.png
|   |-- host_input.png
|   `-- services_select.png
`-- scripts/
    |-- init.sh
    |-- install.sh
    |-- install-docker.sh
    |-- restart.sh
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

## Variables `.env`

Valeurs gérées par `scripts/init.sh`:

- `HOST_IP`
- `BASIC_AUTH_USERNAME`
- `BASIC_AUTH_PASSWORD_HASH`

Valeurs applicatives (initialisees avec des defaults):

- `GENERIC_TIMEZONE`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_DB`

## Notes

- Les informations relatives à la config db sont à changer manuellement dans le .env.
- Le reseau Docker partage est `web`.
- Le fichier `compose/reverse-proxy/Caddyfile` est genéré automatiquement par `scripts/install.sh`.
- La page d'accueil est servie depuis `html/index.html`.
