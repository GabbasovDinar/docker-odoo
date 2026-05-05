# docker-odoo

Production-oriented Docker setup for Odoo 18 with PostgreSQL, Redis sessions,
kwkhtmltopdf, Caddy reverse proxy, persistent volumes, and backup/restore
scripts.

The stack has one default mode: production topology. Use `.env` by default.
For local or staging copies, pass another env file explicitly.

## Structure

```text
.
├── addons/
│   ├── Dockerfile
│   ├── addons.yml
│   └── requirements.txt
├── base/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── config/odoo.conf.tpl
│   ├── manifests/enterprise.yml
│   └── scripts/
├── caddy/
│   └── Caddyfile
├── local-addons/
├── scripts/
│   ├── backup.sh
│   └── restore.sh
├── docker-compose.yml
├── .env.example
├── .dockerignore
├── .gitignore
├── makefile
└── README.md
```

## First Run

Create the env file:

```bash
cp .env.example .env
```

Edit `.env` before starting:

```dotenv
DB_PASSWORD=<strong-random-secret>
ADMIN_PASSWORD=<strong-random-secret>
REDIS_PASSWORD=<strong-random-secret>
CADDY_DOMAIN=odoo.example.com
CADDY_EMAIL=admin@example.com
ODOO_BASE_URL=https://odoo.example.com
```

The Makefile refuses to start with placeholder secrets or example domains.

Build and start:

```bash
make init
make config
make up
make ps
make log-odoo
```

Default Makefile values:

```bash
ENV_FILE=.env
COMPOSE_PROJECT_NAME=docker-odoo
```

Use another env file when needed:

```bash
make up ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
```

## Build Secrets for Private Repositories

Addon and Enterprise build steps read Git tokens from Docker build secrets backed by host environment variables.
Before running `make build-base`, `make build-addons`, or `make init`, provide `GITHUB_TOKEN`, `GITLAB_TOKEN`, and/or `GIT_TOKEN` to Docker Compose.
You can keep them in your selected env file (for example `.env` / `ENV_FILE=...`) — manual `export` is optional and only needed if you do not use an env file.

`ODOO_ENTERPRISE_REPO` can target non-GitHub hosts, but `ODOO_EE_GIT_HOST` must match the repository URL host for private clone authentication.

In `docker-compose.yml` secrets declared with `environment:` must use the variable name (for example `environment: GITHUB_TOKEN`), not `${GITHUB_TOKEN}`.

## Local Use

For local work, keep the production topology and use a local domain.

Example `.env.local` changes:

```dotenv
CADDY_DOMAIN=odoo.localhost
CADDY_EMAIL=admin@example.com
ODOO_BASE_URL=https://odoo.localhost
DB_NAME=odoo_local
DB_PASSWORD=<strong-random-secret>
ADMIN_PASSWORD=<strong-random-secret>
REDIS_PASSWORD=<strong-random-secret>
WORKERS=2
LOG_LEVEL=debug
```

Run:

```bash
make init ENV_FILE=.env.local COMPOSE_PROJECT_NAME=docker-odoo-local
make up ENV_FILE=.env.local COMPOSE_PROJECT_NAME=docker-odoo-local
```

Caddy exposes Odoo on ports `80` and `443`. Odoo itself is not published on
`8069`; it is only reachable inside the Docker network.

## Staging

Use a separate env file and project name:

```bash
cp .env.example .env.staging
```

Minimum staging changes:

```dotenv
DB_NAME=odoo_staging
CADDY_DOMAIN=staging-odoo.example.com
ODOO_BASE_URL=https://staging-odoo.example.com
DBFILTER=^odoo_staging$
LOG_LEVEL=info
WORKERS=2
```

Run:

```bash
make init ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
make up ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
make logs ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
```

## Production Defaults

`.env.example` already uses production-safe defaults for topology and Odoo
runtime. Keep these values unless you know why you are changing them:

```dotenv
LIST_DB=False
PROXY_MODE=True
DBFILTER=^odoo$
INIT=
UPDATE=
STOP_AFTER_INIT=
TEST_ENABLE=
LOG_LEVEL=info
WORKERS=2
MAX_CRON_THREADS=1
LIMIT_MEMORY_SOFT=2147483648
LIMIT_MEMORY_HARD=2684354560
LIMIT_TIME_CPU=600
LIMIT_TIME_REAL=1200
LIMIT_TIME_REAL_CRON=2400
LIMIT_REQUEST=8192
```

Deploy:

```bash
make init
make config
make up
make ps
```

## Commands

```bash
make help
make env
make init
make build-base
make build-addons
make rebuild-addons
make up
make stop
make restart
make down
make down-v
make ps
make logs
make log-odoo
make log-db
make log-redis
make log-caddy
make sh
make odoo-shell
make psql
```

## Custom Addons

Repository addons are baked into the image from:

```text
addons/addons.yml
```

Local addons are mounted from:

```text
local-addons/ -> /opt/local-addons
```

The default addons path is:

```dotenv
ADDONS_PATH=/opt/odoo/addons,/opt/extra-addons,/opt/local-addons
```

After changing `addons/addons.yml` or `addons/requirements.txt`:

```bash
make rebuild-addons
make up
```

After adding local modules:

```bash
make restart
```

Update a module:

```bash
make sh
odoo -c /etc/odoo.conf -u <module_name> -d "$DB_NAME" --stop-after-init
make restart
```

## Backup and Restore

Create a timestamped backup:

```bash
make backup
```

Create a named backup:

```bash
make backup NAME=before-upgrade
```

Restore:

```bash
make restore BACKUP=backups/before-upgrade
```

For another env/project:

```bash
make backup ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging NAME=before-upgrade
make restore ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging BACKUP=backups/before-upgrade
```

Backup includes:

```text
db.dump
filestore.tar.gz
manifest.txt
```

## Validation

```bash
make config
make init
make up
make ps
make log-odoo
make log-db
make psql
make sh
bash -n scripts/backup.sh
bash -n scripts/restore.sh
```

Inside the Odoo shell container:

```bash
odoo --version
grep -E '^(addons_path|data_dir|db_host|db_port|db_user|proxy_mode|workers|list_db|dbfilter|server_wide_modules)' /etc/odoo.conf
find /opt/local-addons -maxdepth 2 -name __manifest__.py
find /opt/extra-addons -maxdepth 2 -name __manifest__.py | head
ls -lah /var/lib/odoo
```

## Notes

- `.env`, `.env.local`, and `.env.staging` are gitignored.
- PostgreSQL and Redis are not published to the host.
- Odoo is not published directly; Caddy is the public entrypoint.
- Use separate `COMPOSE_PROJECT_NAME` values when running multiple stacks on one host.
