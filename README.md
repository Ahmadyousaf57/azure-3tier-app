# 3-Tier Web App on Azure (CLI / Infrastructure as Code)

A 3-tier web application (Nginx -> Node.js/Express -> MySQL) built on Azure entirely with the Azure CLI, so the infrastructure is reproducible from a script instead of console clicks.

## Architecture

    Internet
       |  :80
    [ vm-frontend ]  snet-frontend 10.0.1.0/24   Nginx: serves form, reverse-proxies /api/*
       |  :3000
    [ vm-backend ]   snet-backend  10.0.2.0/24   Node.js + Express, run by PM2, no public IP
       |  :3306
    [ MySQL Flexible Server ]  snet-db 10.0.3.0/24   private access only (delegated subnet)

| Tier | Azure resource | Network rule (NSG) |
|---|---|---|
| Frontend | VM (Ubuntu 22.04, B1s) + public IP | HTTP 80 from anywhere, SSH 22 from admin IPs only |
| Backend | VM (Ubuntu 22.04, B1s), no public IP | 3000 and 22 from frontend subnet only |
| Database | MySQL 8.0 Flexible Server (Burstable B1ms) | 3306 from backend subnet only |

All resources live in one resource group, so cleanup is a single command.

## Repo layout

    scripts/deploy.sh        Azure CLI: network, NSGs, VMs, MySQL
    backend/index.js         Express API: GET/POST /api/users
    backend/.env.example     Template for secrets (real .env is git-ignored)
    frontend/index.html      Simple form + saved users list
    frontend/nginx-default.conf   Nginx site config with reverse proxy

## Usage

Prerequisites: Azure CLI (`az login` done), an Azure subscription, a region allowed by your subscription policy.

    export MYSQL_NAME=<globally-unique-name>
    export ADMIN_IPS="<your-ip>/32"        # space-separated if several
    ./scripts/deploy.sh                    # prompts for the DB password

Then configure the VMs:

1. SSH to the frontend VM, install Nginx, copy `frontend/index.html` to `/var/www/html/` and `frontend/nginx-default.conf` to `/etc/nginx/sites-available/default` (set the backend private IP), then restart Nginx.
2. SSH to the backend VM through the frontend VM (jump host), install Node.js, copy `backend/`, create `.env` from `.env.example`, run `npm install`, start with PM2.

## Security notes

- No secrets in the repo: DB password comes from a prompt/`.env`, both git-ignored.
- Backend and database have no public IP; access is restricted by NSG rules.
- SSH uses key authentication only; port 22 on the frontend is limited to admin IPs.
- Lab simplifications: the DB connection uses SSL without certificate verification (production should pin Azure's CA certificate), and the backend has outbound internet for package installs.

## Status

The commands in `deploy.sh` were first run and verified one by one; the assembled script itself has only been syntax-checked, not run end-to-end.

## Cleanup

    az group delete -n rg-3tier-prod --yes --no-wait

## Next steps

- Convert the infrastructure to Terraform.
- Automate VM configuration (cloud-init or Ansible).
