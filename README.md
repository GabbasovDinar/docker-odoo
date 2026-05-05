# docker-odoo

`docker-odoo` is a Docker Compose project for building and running Odoo from source with custom addons. It uses a two-stage image build, PostgreSQL, Redis-backed sessions, internal `kwkhtmltopdf`, and Caddy as the public entrypoint. Odoo core is installed in the `base/` image, extra addon repositories are pulled during the `addons/` image build, local modules are mounted from `local-addons/`, and runtime configuration is generated from `.env` into `/etc/odoo.conf`.

## Stack

- Odoo
- PostgreSQL
- Docker / Docker Compose
- Caddy reverse proxy
- Redis for Odoo sessions
- `kwkhtmltopdf` for report rendering
- Remote addons from `addons/addons.yml`
- Local custom addons from `local-addons/`


## Minimum Requirements

- Docker Engine with Compose v2
- free host ports `80` and `443`
- a hostname for `CADDY_DOMAIN` that resolves to the current machine or server
- outbound network access during image build to GitHub, GitLab, apt, npm, and image registries
- write access to `backups/`
- read access to `local-addons/`

Required env values before first real use:

- `ADMIN_PASSWORD`
- `DB_PASSWORD`
- `REDIS_PASSWORD`
- `CADDY_DOMAIN`
- `CADDY_EMAIL`
- `ODOO_BASE_URL`

Optional but often needed:

- `GITHUB_TOKEN`, `GITLAB_TOKEN`, `GIT_TOKEN` for private addon repositories
- `ODOO_EE_GIT_TOKEN` for Odoo Enterprise builds

## Minimum Setup

Copy the example env file:

```bash
cp .env.example .env
```

For a local run, the minimum useful values are:

```env
ODOO_VERSION=19.0
ODOO_EDITION=ce
DATABASE_NAME=odoo
DB_NAME=${DATABASE_NAME}
DB_USER=odoo
DB_PASSWORD=CHANGE_ME_STRONG_RANDOM_DB_PASSWORD
ADMIN_PASSWORD=CHANGE_ME_STRONG_RANDOM_ADMIN_PASSWORD
REDIS_PASSWORD=CHANGE_ME_STRONG_RANDOM_REDIS_PASSWORD
WORKERS=2
LIST_DB=False
DBFILTER=^odoo$
CADDY_DOMAIN=localhost
CADDY_EMAIL=admin@example.com
ODOO_BASE_URL=https://localhost
ODOO_REPORT_URL=http://odoo:8069
LOAD=web,session_redis
```

Notes:

- `CADDY_DOMAIN=localhost` is fine for local usage.
- `ODOO_BASE_URL` should match the public URL you will actually open in the browser.
- `ODOO_REPORT_URL` should stay internal as `http://odoo:8069` in this stack.
- `LOAD=web,session_redis` is the current default because Redis session storage is part of this project.

If you need raw Odoo config entries that are not explicitly exposed as separate env vars, use `ODOO_EXTRA_OPTS`. Its content is appended verbatim to the generated `odoo.conf`. This is useful for addons that require extra config blocks in `odoo.conf`, for example OCA `queue_job`.

## First Launch

Build images and start the stack:

```bash
make init
make up
make ps
```

Open Odoo in the browser:

- local: `https://localhost`
- server: `https://<CADDY_DOMAIN>`

If the database does not exist yet:

1. open `https://<CADDY_DOMAIN>/web/database/manager`
2. create a database with the same name as `DB_NAME`
3. use `ADMIN_PASSWORD` as the master password

If you want raw Compose commands instead of `make`:

```bash
docker compose --env-file .env --profile build build odoo-core
docker compose --env-file .env build odoo
docker compose --env-file .env up -d
docker compose --env-file .env ps
```

## Main Commands

For the normal workflow:

- `make init` builds the reusable base image and then the project Odoo image with remote addons.
- `make up` starts PostgreSQL, Redis, `kwkhtmltopdf`, Odoo, and Caddy in the background.
- `make ps` shows whether the containers are up and healthy.
- `make logs` tails logs from the full stack when you want to see startup or runtime errors.

For day-to-day work:

- `make restart` restarts services after changing `.env` or after updating local modules.
- `make stop` stops containers but keeps them available for a later `make up`.
- `make down` removes containers and networks but keeps named volumes and data.
- `make sh` opens a shell inside the Odoo container.
- `make odoo-shell` opens `odoo shell --no-http` inside the running Odoo container.
- `make psql` opens a PostgreSQL shell against the configured database.

For diagnostics:

- `make log-odoo` follows only Odoo logs.
- `make log-db` follows only PostgreSQL logs.
- `make config` prints the final Compose configuration after env interpolation.

For maintenance:

- `make backup` creates a database and filestore backup under `backups/`.
- `make restore BACKUP=backups/<name>` restores a previously created backup.

Use a different env file or project name when needed:

```bash
make up ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
```

## Odoo CE / EE

This project supports both Odoo Community Edition and Odoo Enterprise Edition.

For Community Edition:

```env
ODOO_EDITION=ce
ODOO_VERSION=19.0
```

For Enterprise Edition:

```env
ODOO_EDITION=ee
ODOO_VERSION=19.0
ODOO_ENTERPRISE_REPO=https://github.com/odoo/enterprise.git
ODOO_EE_GIT_TOKEN=your_token
ODOO_EE_GIT_USER=x-access-token
ODOO_EE_GIT_HOST=github.com
```

Then rebuild the images:

```bash
make init
make up
```

Notes:

- `ODOO_EDITION=ee` enables the Enterprise build path in `base/Dockerfile`.
- Enterprise addons are installed into `${ODOO_EE_ADDONS_DIR}`.
- The runtime automatically appends `${ODOO_EE_ADDONS_DIR}` to `addons_path`.
- If you want reproducible Enterprise builds, also set `ODOO_ENTERPRISE_REF`.
- If your Enterprise repository is hosted outside GitHub, set matching `ODOO_EE_GIT_HOST`, `ODOO_EE_GIT_USER`, and `ODOO_EE_GIT_TOKEN`.

## Working with Odoo Modules

### Where modules come from

- core Odoo addons: `/opt/odoo/addons`
- remote addons baked into the image: `/opt/extra-addons`
- local project addons: `/opt/local-addons`

Default runtime `addons_path`:

```text
/opt/odoo/addons,/opt/extra-addons,/opt/local-addons
```

If `ODOO_EDITION=ee`, the runtime also appends `${ODOO_EE_ADDONS_DIR}` automatically.

### Add a local custom module

Put the module in `local-addons/`:

```text
local-addons/
  my_module/
    __init__.py
    __manifest__.py
    ...
```

Then restart Odoo:

```bash
make restart
```

If the module has Python dependencies, add them to `addons/requirements.txt` and rebuild the `odoo` image:

```bash
make build-addons
make up
```

### Add a new remote addon repository

Edit `addons/addons.yml` and add another repo entry in the same format already used there. This file is processed by `git-aggregator`, so if you need the full manifest format, merge syntax, or advanced options, use the upstream documentation: [git-aggregator](https://github.com/acsone/git-aggregator).

Then rebuild the addons image:

```bash
make build-addons
make up
```

### Install or update a module

Update one module from CLI:

```bash
docker compose exec odoo bash -lc 'odoo -c /etc/odoo.conf -d "$DB_NAME" -u module_name --stop-after-init'
```

After that restart Odoo:

```bash
make restart
```

## Advanced Settings

This section contains the project internals and lower-level runtime details.

### Config rendering

- `.env` is mounted into the container as `/run/odoo/.env`
- `/etc/odoo.conf` is rendered from `base/config/odoo.conf.tpl`
- unresolved or empty config lines are dropped during rendering
- `ODOO_EXTRA_OPTS` is appended at the end of the generated config

That means you can inject extra Odoo config without modifying the template.

### Ports

- host ports:
  - `80:80`
  - `443:443`
  - `443:443/udp`
- internal-only services:
  - Odoo HTTP: `8069`
  - Odoo XML-RPCS: `8071`
  - Odoo gevent/websocket: `8072`
  - PostgreSQL: `5432`
  - Redis: `6379`
  - `kwkhtmltopdf`: `8080`

### Volumes

- `db-data` -> `/var/lib/postgresql/data`
- `odoo-data` -> `/var/lib/odoo`
- `redis-data` -> `/data`
- `caddy-data` -> `/data`
- `caddy-config` -> `/config`
- `${LOCAL_ADDONS_DIR}` -> `/opt/local-addons`

### Data locations

- PostgreSQL data: `db-data`
- Odoo filestore: `/var/lib/odoo/filestore/${DB_NAME}`
- Redis persistence: `redis-data`
- Caddy certificates and state: `caddy-data`, `caddy-config`

### Addons build behavior

- `addons/addons.yml` is processed by `git-aggregator`
- module directories are copied into `/opt/extra-addons`
- Python and Debian dependencies are resolved from addon metadata during build
- `addons/requirements.txt` is installed into the image during the addons build stage

### Redis sessions

- default `LOAD` includes `session_redis`
- Redis is private to Docker Compose and not published to the host
- Odoo uses `REDIS_PASSWORD`
- old filesystem sessions are cleaned up by the entrypoint when Redis session storage is enabled

### Reverse proxy

- public traffic goes to Caddy, not directly to Odoo
- `caddy/Caddyfile` proxies:
  - normal HTTP traffic to `odoo:8069`
  - `/longpolling/*` and `/websocket` to `odoo:8072`
- `PROXY_MODE=True` is expected for this topology

### Local vs server use

This repository does not have a separate dev compose file. Local, staging, and production separation is done through:

- different `.env` files
- different `COMPOSE_PROJECT_NAME`

Examples:

```bash
make up ENV_FILE=.env.local COMPOSE_PROJECT_NAME=docker-odoo-local
make up ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
make up ENV_FILE=.env.prod COMPOSE_PROJECT_NAME=docker-odoo-prod
```

### Production / staging notes

There is no `docker-compose.prod.yml` in this repository.

What is already production-friendly in the current project:

- PostgreSQL is not published to the host
- Redis is not published to the host
- Odoo is not published directly to the host
- named volumes persist database, filestore, Redis, and Caddy state
- reverse proxy handling is already configured

What you still need to set correctly per environment:

- `CADDY_DOMAIN`
- `CADDY_EMAIL`
- `ODOO_BASE_URL`
- `ADMIN_PASSWORD`
- `DB_PASSWORD`
- `REDIS_PASSWORD`
- `WORKERS`
- `LIST_DB`
- `DBFILTER`

### Password rotation caveat

Changing `DB_PASSWORD` for an already initialized PostgreSQL volume is not just an env change. The existing `db-data` volume keeps the original PostgreSQL credentials, so password rotation requires an intentional PostgreSQL-side change or volume re-creation.

## Backup

Use the built-in scripts:

```bash
make backup
make backup NAME=before-upgrade
```

Direct usage:

```bash
./scripts/backup.sh
./scripts/backup.sh before-upgrade
```

The backup creates `backups/<timestamp-or-name>/` with:

- `db.dump`
- `filestore.tar.gz`
- `manifest.txt`

What is backed up:

- PostgreSQL database `${DB_NAME}`
- Odoo filestore from `${DATA_DIR}/filestore/${DB_NAME}`

## Restore

Restore overwrites the current database and filestore for `${DB_NAME}`.

Restore a backup:

```bash
make restore BACKUP=backups/2026-05-05_12-00-00
```

Direct usage:

```bash
./scripts/restore.sh backups/2026-05-05_12-00-00
```

Restore flow:

- stop `odoo`
- restore `db.dump` into PostgreSQL
- delete `${DATA_DIR}/filestore/${DB_NAME}`
- extract `filestore.tar.gz`
- start `odoo`

## Security

- do not commit `.env`
- replace all `CHANGE_ME_*` values before real use
- keep PostgreSQL private
- keep Redis private
- run public deployments behind Caddy or another reverse proxy
- do not store backups in Git
- keep `ADMIN_PASSWORD` strong

## References

* [Odoo 19 documentation](https://www.odoo.com/documentation/19.0/)
* [git-aggregator](https://github.com/acsone/git-aggregator)
* [Docker Compose CLI reference](https://docs.docker.com/engine/reference/commandline/compose/)
* [Caddy documentation](https://caddyserver.com/docs/)
* [kwkhtmltopdf](https://github.com/acsone/kwkhtmltopdf)
