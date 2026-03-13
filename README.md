# Homelab

Repo d'infrastructure pour déployer rapidement un petit homelab Docker sur Raspberry Pi ou mini-PC Debian/Ubuntu-like.

## Contenu

- Caddy reverse proxy
- Portainer
- n8n
- Gokapi
- Postgres
- Netdata
- Homepage HTML statique

## Structure

```text
homelab/
├── .env.example
├── .gitignore
├── install.sh
├── up.sh
├── update.sh
├── compose/
│   ├── reverse-proxy/
│   │   ├── compose.yml
│   │   └── Caddyfile
│   ├── n8n/
│   │   └── compose.yml
│   ├── gokapi/
│   │   └── compose.yml
│   ├── postgres/
│   │   ├── compose.yml
│   │   └── init.sql
│   └── netdata/
│       └── compose.yml
└── html/
    └── index.html
```

## Installation

```bash
chmod +x install.sh up.sh update.sh
./install.sh
newgrp docker
```

`install.sh` ouvre une interface CLI (checkbox) pour choisir les services a installer/deployer.

## Variables

Les variables sont définies dans `.env`.

- `GENERIC_TIMEZONE`
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_DB`

`HOST_IP` n'est plus requis dans `.env` : il est detecte automatiquement par les scripts (`install.sh`, `up.sh`, `update.sh`).

Gokapi est preconfigure par son wizard accessible sur `/gokapi/setup`.

## Remarques

- Le réseau Docker partagé s'appelle `web`
- Les volumes Docker ne sont pas versionnés
- En cas de migration vers une autre machine, clone le repo, ajuste `.env`, puis relance les scripts
