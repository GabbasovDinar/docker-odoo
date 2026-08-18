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
- OCA OpenUpgrade on branches that provide the migration workflow

## Minimum Requirements

- Docker Engine with Compose v2
- GNU Make
- free host ports `80` and `443`
- a hostname for `CADDY_DOMAIN` that resolves to the current machine or server
- outbound network access during image build to GitHub, GitLab, apt, npm, and image registries
- write access to `backups/`
- read access to `local-addons/`

Required env values before first real use:

- `ODOO_VERSION`
- `ADMIN_PASSWORD`
- `DB_USER`
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

Set `ODOO_VERSION` to the checked-out branch version. For example, on branch `17.0`:

```env
ODOO_VERSION=17.0
ODOO_EDITION=ce
DATABASE_NAME=odoo
DB_NAME=${DATABASE_NAME}
DB_HOST=db
DB_PORT=5432
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
- `DB_HOST=db` uses the bundled PostgreSQL container. Set `DB_HOST` to a DNS name or IP to use PostgreSQL on another machine.

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
- `make build` is an alias for the normal build flow.
- `make build-base` builds only the reusable core image.
- `make build-addons` builds only the project addons image.
- `make rebuild-addons` rebuilds the addons image without cache.
- `make pull` pulls runtime images.
- `make up` starts the stack in the background.
- `make start` is an alias for `make up`.
- `make ps` shows service status.
- `make logs` follows logs from the full stack.

For day-to-day work:

- `make restart` restarts services after changing `.env` or after updating local modules.
- `make stop` stops containers but keeps them available for a later `make up`.
- `make down` removes containers and networks but keeps named volumes and data.
- `make down-v` also removes named volumes. Use it only when you intentionally want to delete persistent Docker data.
- `make sh` opens a shell inside the Odoo container.
- `make odoo-shell` opens `odoo shell --no-http` inside the running Odoo container.
- `make psql` opens a PostgreSQL shell against the bundled Compose PostgreSQL service.
- `make env` prints the Make/Compose environment currently being used.

For diagnostics:

- `make log-odoo` follows only Odoo logs.
- `make log-db` follows only PostgreSQL logs.
- `make log-redis` follows only Redis logs.
- `make log-caddy` follows only Caddy logs.
- `make log-wkhtmltopdf` follows only `kwkhtmltopdf` logs.
- `make config` prints the final Compose configuration after env interpolation.

For maintenance:

- `make backup` creates a database and filestore backup under `backups/`.
- `make restore BACKUP=backups/<name>` restores a previously created backup.
- `make prune` removes Docker build cache.

For OpenUpgrade:

- `make migrate` runs the migration once in a disposable Odoo container and writes the complete migration output to `migration.log`.

Use a different env file or project name when needed:

```bash
make up ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
```

The same pattern works for all Make targets, including migrations:

```bash
make migrate ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
```

## Odoo CE / EE

This project supports both Odoo Community Edition and Odoo Enterprise Edition.

For Community Edition:

```env
ODOO_EDITION=ce
ODOO_VERSION=<current-branch-version>
```

For Enterprise Edition:

```env
ODOO_EDITION=ee
ODOO_VERSION=<current-branch-version>
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
- For reproducible Enterprise builds, set `ODOO_ENTERPRISE_REF` to the required branch, tag, or commit.
- For reproducible Community builds, use `ODOO_CE_REF` when needed.
- If the Enterprise repository is hosted outside GitHub, set matching `ODOO_EE_GIT_HOST`, `ODOO_EE_GIT_USER`, and `ODOO_EE_GIT_TOKEN`.

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

Edit `addons/addons.yml` and add another repository entry in the same format already used there. This file is processed by `git-aggregator`.

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

## PostgreSQL: Bundled or External

By default the project can use the bundled PostgreSQL service:

```env
DB_HOST=db
DB_PORT=5432
DB_USER=odoo
DB_PASSWORD=CHANGE_ME_DB_PASSWORD
```

To use PostgreSQL on another VM or server, point `DB_HOST` to that server:

```env
DB_HOST=10.20.0.15
DB_PORT=5432
DB_USER=odoo
DB_PASSWORD=CHANGE_ME_DB_PASSWORD
```

The Docker host must be able to reach the PostgreSQL server on TCP port `5432`:

```bash
nc -zv 10.20.0.15 5432
```

On the PostgreSQL VM, `listen_addresses` and `pg_hba.conf` must allow the Docker/Odoo host. Prefer a specific source address or subnet, for example:

```conf
host    all    odoo    10.20.0.25/32    scram-sha-256
```

Do not expose PostgreSQL to the public Internet unless it is explicitly required and protected by appropriate network controls.

When `DB_HOST` points to another machine, Odoo uses that external PostgreSQL endpoint. The Compose `db` service may still exist in the project topology, but application database connections are controlled by `DB_HOST` / `DB_PORT`.

## OpenUpgrade Migrations

OpenUpgrade is used to migrate an existing database one Odoo major version at a time.

### Source and Target Database Model

The source database is never migrated in place.

For each hop the migration workflow is:

```text
OPENUPGRADE_SOURCE_DATABASE_NAME
              |
              | pg_dump / pg_restore
              v
OPENUPGRADE_TARGET_DATABASE_NAME
              |
              | OpenUpgrade -u all
              v
migrated target database
```

Example for `16.0 -> 17.0`:

```env
ODOO_VERSION=17.0
OPENUPGRADE=True
OPENUPGRADE_SOURCE_DATABASE_NAME=ODOO_16
OPENUPGRADE_TARGET_DATABASE_NAME=ODOO_17
OPENUPGRADE_TARGET_VERSION=17.0
OPENUPGRADE_RECREATE_DATABASE=False
OPENUPGRADE_FORCE=False
OPENUPGRADE_COPY_FILESTORE=True
```

The result is:

```text
ODOO_16    unchanged source database
ODOO_17    copy of ODOO_16, migrated to Odoo 17
```

Use `openupgrade.env.example` as the starting point on branches that contain the OpenUpgrade workflow.

### Running a Migration

Build the target-version images first:

```bash
make init ENV_FILE=.env.migrate
```

Then run the migration explicitly:

```bash
make migrate ENV_FILE=.env.migrate
```

`make migrate`:

1. overwrites the previous `migration.log`;
2. stops the normal Odoo service if it is running;
3. starts a disposable Odoo container with the `openupgrade` entrypoint command;
4. clones the source database into the target database;
5. runs OpenUpgrade against the target database only;
6. writes stdout and stderr to `migration.log` while still showing them in the terminal;
7. preserves the OpenUpgrade exit code through `pipefail`;
8. exits when the migration finishes.

After a successful migration, start normal Odoo:

```bash
make up ENV_FILE=.env.migrate
make log-odoo ENV_FILE=.env.migrate
```

### Migration Log

Every `make migrate` run writes to a single file in the repository root:

```text
migration.log
```

The previous file is overwritten at the beginning of every migration run. The file contains the complete stdout/stderr stream produced by the Make target, Docker Compose, the entrypoint, PostgreSQL client tools, Odoo, and OpenUpgrade.

The same output is shown in the terminal through `tee`.

Inspect the log after a failure:

```bash
less migration.log
```

or:

```bash
tail -n 200 migration.log
```

`migration.log` is ignored by Git.

### Migration with PostgreSQL on Another VM

The migration container does not require PostgreSQL to be on the same machine. Point `DB_HOST` at the external PostgreSQL VM:

```env
DB_HOST=10.20.0.15
DB_PORT=5432
DB_USER=odoo_migration
DB_PASSWORD=CHANGE_ME_DB_PASSWORD

OPENUPGRADE=True
OPENUPGRADE_SOURCE_DATABASE_NAME=production16
OPENUPGRADE_TARGET_DATABASE_NAME=migration17
```

Current source-to-target cloning expects both databases to be on the same configured PostgreSQL endpoint:

```text
Migration VM                         PostgreSQL VM
Docker / OpenUpgrade                10.20.0.15:5432
+----------------------+            +----------------------+
| pg_dump / pg_restore |----------->| production16         |
| Odoo target version  |            | migration17          |
+----------------------+            +----------------------+
```

The migration role must be able to:

- connect to the source database;
- read all source objects required by `pg_dump`;
- create the target database;
- restore schema and data into the target database;
- drop the target database when `OPENUPGRADE_RECREATE_DATABASE=True`.

For a dedicated migration role this normally includes `CREATEDB`:

```sql
ALTER ROLE odoo_migration CREATEDB;
```

Grant only the additional source-database permissions required by your PostgreSQL ownership and ACL model.

### What Happens Internally

With `OPENUPGRADE=True`, the one-shot migration container:

1. validates that source and target database names are present and different;
2. verifies that the source database exists;
3. creates the target database with `createdb`;
4. clones source into target with `pg_dump --format=custom | pg_restore`;
5. optionally copies the source filestore to the target filestore;
6. runs Odoo with `openupgrade_framework`, `-u all`, `--stop-after-init`, `--no-http`, zero workers and zero cron threads;
7. verifies that the target `base` module reports the current branch major version;
8. records a successful migration marker in `ir_config_parameter`;
9. exits successfully.

The source database is read by `pg_dump`; the target-version Odoo process is not started against the source database.

### Existing Target Database Safety

The target database is not overwritten by default.

If the target already contains a matching successful migration marker, OpenUpgrade is skipped for that completed hop.

If the target exists without the successful marker, migration stops with an error. This includes a target left by a failed or partial migration.

To intentionally discard the target and recreate it from the source:

```env
OPENUPGRADE_RECREATE_DATABASE=True
```

Then rerun:

```bash
make migrate ENV_FILE=.env.migrate
```

This drops only `OPENUPGRADE_TARGET_DATABASE_NAME`, recreates it from the source, and reruns the migration.

`OPENUPGRADE_FORCE=True` is intended for an explicit rerun on an already completed target. For a clean retry after a failed migration, prefer `OPENUPGRADE_RECREATE_DATABASE=True`.

Never configure the same database name as both source and target.

### Filestore During Migration

PostgreSQL cloning does not clone the Odoo filestore.

With:

```env
OPENUPGRADE_COPY_FILESTORE=True
```

the entrypoint tries to copy:

```text
${DATA_DIR}/filestore/<source_database>
    ->
${DATA_DIR}/filestore/<target_database>
```

This only works when the source filestore is visible inside the migration container under the expected `DATA_DIR` path.

If the source database is on a PostgreSQL VM and the source filestore is on another Odoo VM, copy or mount the source filestore into the migration Odoo data volume before running `make migrate`.

For example, first copy the files from the old Odoo server to the migration host:

```bash
rsync -a \
  odoo@old-odoo-vm:/var/lib/odoo/filestore/production16/ \
  /path/to/source-filestore/production16/
```

Then ensure that the content is available inside the migration container as:

```text
/var/lib/odoo/filestore/production16
```

If the source filestore is not visible, the entrypoint logs a warning and continues with the database migration. Attachments, documents, images, and other filestore-backed records cannot be fully validated until the filestore is available.

### Custom Migration Scripts

All installed custom/OCA addons from the source database must have code compatible with the target Odoo version before migration.

Module-local migration scripts should live in the addon itself, for example:

```text
my_module/
  migrations/
    17.0.1.0.0/
      pre-migration.py
      post-migration.py
```

or in the corresponding `upgrades/` directory supported by the target Odoo version.

For project-wide external scripts use the configured upgrade path:

```env
UPGRADE_PATH=/opt/local-addons/upgrade
```

Before a real migration it is useful to inspect installed modules in the source database:

```sql
SELECT name, latest_version
FROM ir_module_module
WHERE state = 'installed'
ORDER BY name;
```

Every installed source module must be present in a compatible target-version form or intentionally handled by migration logic.

### Recommended Multi-hop Procedure

For every hop:

1. checkout the target Odoo branch;
2. copy `openupgrade.env.example` to a dedicated migration env file;
3. set the target branch `ODOO_VERSION`;
4. configure unique source and target database names;
5. verify PostgreSQL connectivity and permissions;
6. make the source filestore available if the database uses filestore-backed attachments;
7. build with `make init ENV_FILE=<migration-env>`;
8. run `make migrate ENV_FILE=<migration-env>`;
9. inspect `migration.log` if anything fails;
10. for a clean retry, set `OPENUPGRADE_RECREATE_DATABASE=True` and rerun `make migrate`;
11. after success, run `make up ENV_FILE=<migration-env>` and functionally validate Odoo;
12. use that successfully migrated target database as the source for the next major-version hop.

Example `16 -> 17`:

```bash
git switch 17.0
cp openupgrade.env.example .env.migrate-17
# edit .env.migrate-17
make init ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
make migrate ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
make up ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
```

Do not continue to the next major version from a database whose current hop has not been validated.

## Advanced Settings

This section contains the project internals and lower-level runtime details.

### Config Rendering

- `.env` is mounted into the container as `/run/odoo/.env`.
- `/etc/odoo.conf` is rendered from `base/config/odoo.conf.tpl`.
- unresolved or empty config lines are dropped during rendering.
- `ODOO_EXTRA_OPTS` is appended to the generated config.

This allows extra Odoo configuration without modifying the template.

### Ports

Host ports:

- `80:80`
- `443:443`
- `443:443/udp`

Internal services:

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

### Data Locations

- PostgreSQL data: `db-data`
- Odoo filestore: `/var/lib/odoo/filestore/${DB_NAME}`
- Redis persistence: `redis-data`
- Caddy certificates and state: `caddy-data`, `caddy-config`

### Addons Build Behavior

- `addons/addons.yml` is processed by `git-aggregator`.
- module directories are copied into `/opt/extra-addons`.
- Python and Debian dependencies are resolved from addon metadata during build.
- `addons/requirements.txt` is installed into the image during the addons build stage.

### Redis Sessions

- default `LOAD` includes `session_redis`.
- Redis is private to Docker Compose and is not published to the host.
- Odoo uses `REDIS_PASSWORD`.
- old filesystem sessions are cleaned up by the entrypoint when Redis session storage is enabled.

### Reverse Proxy

Public traffic goes to Caddy, not directly to Odoo.

`caddy/Caddyfile` proxies:

- normal HTTP traffic to `odoo:8069`;
- `/longpolling/*` and `/websocket` to `odoo:8072`.

`PROXY_MODE=True` is expected for this topology.

### Nginx with a Custom TLS Certificate

If TLS termination is already managed by an external Nginx instance and you want to use your own certificate instead of the bundled Caddy service, keep Odoo behind the reverse proxy and let Nginx expose only ports `80` and `443` to clients.

Recommended topology when Nginx runs directly on the Docker host:

```text
Internet
   |
   | HTTPS :443
   v
Nginx on host
   |
   +---- 127.0.0.1:8069 ----> Odoo HTTP
   |
   +---- 127.0.0.1:8072 ----> Odoo websocket/gevent

Docker private network:
Odoo <----> PostgreSQL
Odoo <----> Redis
Odoo <----> kwkhtmltopdf
```

#### Disable the bundled Caddy service

The default Compose configuration starts Caddy and publishes host ports `80` and `443`. If host-level Nginx already owns those ports, Caddy must not be started.

For a dedicated Nginx deployment, remove or override the `caddy` service from `docker-compose.yml`. The Caddy-only volumes can also be removed when they are no longer used:

```yaml
volumes:
  # caddy-data:    # remove when Caddy is not used
  # caddy-config:  # remove when Caddy is not used
```

The following variables are Caddy-specific and are not required by Nginx:

```env
CADDY_DOMAIN=
CADDY_EMAIL=
```

Do not run Caddy and host-level Nginx on the same host ports unless you intentionally place one proxy behind the other.

#### Publish Odoo only on localhost

The current Compose configuration uses `expose` because Caddy reaches Odoo through the Docker network. A host-level Nginx cannot use Docker service names directly, so publish the Odoo HTTP and realtime ports only on loopback:

```yaml
odoo:
  expose:
    - "8069"
    - "8072"
  ports:
    - "127.0.0.1:8069:8069"
    - "127.0.0.1:8072:8072"
```

Use `127.0.0.1`, not `0.0.0.0`, so clients cannot bypass Nginx and connect directly to Odoo.

Do not publish PostgreSQL, Redis, or `kwkhtmltopdf` for this setup. They should stay on private Docker networks.

#### Odoo environment settings

Use the public HTTPS address for `web.base.url`, but keep report rendering and `kwkhtmltopdf` traffic internal:

```env
ODOO_BASE_URL=https://odoo.example.com
ODOO_BASE_URL_FREEZE=True
PROXY_MODE=True

ODOO_REPORT_URL=http://odoo:8069
KWKHTMLTOPDF_SERVER_URL=http://kwkhtmltopdf:8080
```

Important distinctions:

- `ODOO_BASE_URL` is the public URL opened by users and therefore uses HTTPS.
- `ODOO_REPORT_URL` is an internal Docker URL used when reports need to load Odoo resources; it does not need to pass through Nginx or TLS.
- `KWKHTMLTOPDF_SERVER_URL` is also internal Docker traffic and should normally remain `http://kwkhtmltopdf:8080`.
- `PROXY_MODE=True` must remain enabled so Odoo correctly interprets `X-Forwarded-*` headers from Nginx.

#### Example Nginx configuration

The following example assumes:

```text
Domain:      odoo.example.com
Certificate: /etc/nginx/ssl/odoo.crt
Private key: /etc/nginx/ssl/odoo.key
```

```nginx
map $http_upgrade $connection_upgrade {
    default upgrade;
    ''      close;
}

upstream odoo {
    server 127.0.0.1:8069;
}

upstream odoo_realtime {
    server 127.0.0.1:8072;
}

server {
    listen 80;
    server_name odoo.example.com;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    http2 on;

    server_name odoo.example.com;

    ssl_certificate     /etc/nginx/ssl/odoo.crt;
    ssl_certificate_key /etc/nginx/ssl/odoo.key;

    client_max_body_size 200m;

    proxy_connect_timeout 60s;
    proxy_read_timeout 720s;
    proxy_send_timeout 720s;

    location /websocket {
        proxy_pass http://odoo_realtime;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location /longpolling/ {
        proxy_pass http://odoo_realtime;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
    }

    location / {
        proxy_pass http://odoo;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Proto https;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Replace the domain and certificate paths with the values used by your deployment.

Validate and reload Nginx after changing the configuration:

```bash
sudo nginx -t
sudo systemctl reload nginx
```

Then verify public access:

```bash
curl -I https://odoo.example.com
```

#### If Nginx runs in Docker

If Nginx is another Docker service instead of a host service, do not publish `8069` or `8072` to the host. Connect the Nginx container to the same Docker network as Odoo and proxy directly to:

```text
http://odoo:8069
http://odoo:8072
```

In that topology the Odoo service can continue to use only `expose`, exactly like the bundled Caddy setup.

The TLS certificate and private key should be mounted read-only into the Nginx container. PostgreSQL, Redis, and `kwkhtmltopdf` should remain private and must not be routed through Nginx.

### Local, Staging, and Production Environments

The repository does not require separate Compose files for each environment. Separation can be done with different env files and Compose project names:

```bash
make up ENV_FILE=.env.local COMPOSE_PROJECT_NAME=docker-odoo-local
make up ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
make up ENV_FILE=.env.prod COMPOSE_PROJECT_NAME=docker-odoo-prod
```

Use the same approach for migration environments so they do not collide with normal runtime containers and volumes.

### Production / Staging Notes

The current stack already keeps PostgreSQL, Redis, and Odoo private behind the Compose network and exposes public traffic through Caddy.

Named volumes persist database, filestore, Redis, and Caddy data.

Set these values intentionally per environment:

- `CADDY_DOMAIN`
- `CADDY_EMAIL`
- `ODOO_BASE_URL`
- `ADMIN_PASSWORD`
- `DB_HOST`
- `DB_PORT`
- `DB_USER`
- `DB_PASSWORD`
- `REDIS_PASSWORD`
- `WORKERS`
- `LIST_DB`
- `DBFILTER`

### Password Rotation Caveat

Changing `DB_PASSWORD` for an already initialized bundled PostgreSQL volume is not only an env-file change. The existing `db-data` volume keeps the PostgreSQL role and password already created in the database cluster. Rotate the password on the PostgreSQL side or intentionally recreate the database volume.

For an external PostgreSQL VM, rotate credentials on that external PostgreSQL server and then update the Odoo env file.

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

Before a production migration, keep an independent verified backup of the source database and source filestore even though OpenUpgrade itself works on a cloned target database.

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

- stop `odoo`;
- restore `db.dump` into PostgreSQL;
- delete `${DATA_DIR}/filestore/${DB_NAME}`;
- extract `filestore.tar.gz`;
- start `odoo`.

Verify the configured target environment before running restore because it is destructive for the configured database and filestore.

## Security

- do not commit `.env` or migration-specific env files;
- replace all `CHANGE_ME_*` values before real use;
- keep PostgreSQL private whenever possible;
- keep Redis private;
- run public deployments behind Caddy or another reverse proxy;
- restrict `pg_hba.conf` to the required hosts/subnets;
- do not store backups in Git;
- do not commit `migration.log`;
- keep `ADMIN_PASSWORD` strong;
- use a dedicated migration PostgreSQL role where appropriate;
- validate migrations on cloned target databases before switching production traffic.

## References

- [Odoo 17 documentation](https://www.odoo.com/documentation/17.0/)
- [OCA/OpenUpgrade](https://github.com/OCA/OpenUpgrade)
- [git-aggregator](https://github.com/acsone/git-aggregator)
- [Docker Compose CLI reference](https://docs.docker.com/engine/reference/commandline/compose/)
- [Caddy documentation](https://caddyserver.com/docs/)
- [kwkhtmltopdf](https://github.com/acsone/kwkhtmltopdf)
