# docker-odoo

`docker-odoo` is a Docker Compose project for building and running Odoo from source with custom addons. Each major Odoo version lives in its corresponding repository branch (`17.0`, `18.0`, `19.0`, ...).

The stack includes Odoo, PostgreSQL, Redis-backed sessions, `kwkhtmltopdf`, Caddy, remote addons from `addons/addons.yml`, and local custom addons from `local-addons/`.

## Requirements

- Docker Engine with Compose v2
- free host ports `80` and `443`
- outbound access during image build to GitHub/GitLab/package repositories
- read access to `local-addons/`
- write access to `backups/`

Required environment values for a normal deployment:

- `ODOO_VERSION`
- `ADMIN_PASSWORD`
- `DB_USER`
- `DB_PASSWORD`
- `REDIS_PASSWORD`
- `CADDY_DOMAIN`
- `CADDY_EMAIL`
- `ODOO_BASE_URL`

Optional credentials such as `GITHUB_TOKEN`, `GITLAB_TOKEN`, `GIT_TOKEN`, and `ODOO_EE_GIT_TOKEN` are required only when the corresponding private repositories are used.

## Basic setup

```bash
cp .env.example .env
```

Set `ODOO_VERSION` to the version represented by the checked-out branch, for example:

```env
ODOO_VERSION=18.0
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

Build and start:

```bash
make init
make up
make ps
```

Useful commands:

```bash
make restart
make stop
make down
make logs
make log-odoo
make log-db
make sh
make odoo-shell
make psql
make config
make backup
```

A custom env file/project name can be used for isolated environments:

```bash
make up ENV_FILE=.env.staging COMPOSE_PROJECT_NAME=docker-odoo-staging
```

## Odoo Community / Enterprise

Community:

```env
ODOO_EDITION=ce
ODOO_VERSION=18.0
```

Enterprise:

```env
ODOO_EDITION=ee
ODOO_VERSION=18.0
ODOO_ENTERPRISE_REPO=https://github.com/odoo/enterprise.git
ODOO_EE_GIT_TOKEN=your_token
ODOO_EE_GIT_USER=x-access-token
ODOO_EE_GIT_HOST=github.com
```

For reproducible builds, pin `ODOO_CE_REF` / `ODOO_ENTERPRISE_REF` to the required ref.

## Addons

Addon locations inside the Odoo container:

```text
/opt/odoo/addons
/opt/extra-addons
/opt/local-addons
```

Enterprise builds also append the Enterprise addons directory.

Remote repositories are configured in `addons/addons.yml` and are copied into `/opt/extra-addons` during the addons image build. Local custom modules belong in `local-addons/`.

After changing remote addon dependencies:

```bash
make build-addons
make up
```

To update one module manually:

```bash
docker compose exec odoo bash -lc 'odoo -c /etc/odoo.conf -d "$DB_NAME" -u module_name --stop-after-init'
```

## OpenUpgrade migrations

The version branches can run an OpenUpgrade migration from the immediately preceding major Odoo version. OpenUpgrade must be executed one major version at a time.

Typical chain:

```text
Odoo 16 database
    |
    | branch 17.0
    v
Odoo 17 database
    |
    | branch 18.0
    v
Odoo 18 database
    |
    | branch 19.0
    v
Odoo 19 database
```

### Source and target database model

The source database is never migrated in place.

For every migration hop the entrypoint performs this workflow:

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

Example for `16 -> 17`:

```env
ODOO_VERSION=17.0
OPENUPGRADE=True
OPENUPGRADE_SOURCE_DATABASE_NAME=odoo16
OPENUPGRADE_TARGET_DATABASE_NAME=odoo17
OPENUPGRADE_TARGET_VERSION=18.0
OPENUPGRADE_RECREATE_DATABASE=False
OPENUPGRADE_FORCE=False
OPENUPGRADE_COPY_FILESTORE=True
```

The result is:

```text
odoo16              unchanged source
odoo17              copy of odoo16, then migrated to Odoo 17
```

For the next hop switch to the `18.0` branch and use:

```env
ODOO_VERSION=18.0
OPENUPGRADE=True
OPENUPGRADE_SOURCE_DATABASE_NAME=odoo17
OPENUPGRADE_TARGET_DATABASE_NAME=odoo18
OPENUPGRADE_TARGET_VERSION=18.0
```

For `18 -> 19` on branch `19.0`:

```env
ODOO_VERSION=19.0
OPENUPGRADE=True
OPENUPGRADE_SOURCE_DATABASE_NAME=odoo18
OPENUPGRADE_TARGET_DATABASE_NAME=odoo19
OPENUPGRADE_TARGET_VERSION=19.0
```

`OPENUPGRADE_TARGET_VERSION` is the final destination known to OpenUpgrade. During a multi-hop migration such as `16 -> 17 -> 18`, it may be kept at `18.0` on both hops. The entrypoint validates the completed hop against `ODOO_VERSION`, not against the final target.

A complete starting point is available in `openupgrade.env.example` on branches that support the migration workflow.

### Running a migration

Migration is intentionally separated from normal Odoo startup. Use the dedicated one-shot command:

```bash
make init
make migrate
```

`make migrate` stops the normal `odoo` service if it is running and launches a disposable Compose container with the `openupgrade` entrypoint command. The container exits after the migration finishes, so a failed migration is not automatically restarted by the normal service restart policy.

After a successful migration, start Odoo normally:

```bash
make up
make log-odoo
```

The normal Odoo process is pinned to `OPENUPGRADE_TARGET_DATABASE_NAME` while `OPENUPGRADE=True` is present in the env file. If the target already contains the successful migration marker, the migration is skipped on normal startup and Odoo runs against the migrated target.

You can use another env file for each hop:

```bash
make migrate ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
make up ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
```

### What `make migrate` does

With `OPENUPGRADE=True` the one-shot migration container:

1. validates that source and target names are both set and different;
2. verifies that the source PostgreSQL database exists;
3. creates the target database with `createdb`;
4. clones source into target using `pg_dump --format=custom | pg_restore`;
5. optionally copies the matching Odoo filestore;
6. runs Odoo with `openupgrade_framework`, `-u all`, `--stop-after-init`, `--no-http`, and zero workers/cron threads;
7. verifies that the target `base` module reports the current branch major version;
8. stores a successful migration marker in `ir_config_parameter`;
9. exits successfully.

The source database is only read by `pg_dump`; the new Odoo version is never started against it.

### PostgreSQL on another VM

The migration container does not require PostgreSQL to run on the same VM. Set `DB_HOST` and `DB_PORT` to the external PostgreSQL server:

```env
DB_HOST=10.20.0.15
DB_PORT=5432
DB_USER=odoo_migration
DB_PASSWORD=CHANGE_ME_DB_PASSWORD

OPENUPGRADE=True
OPENUPGRADE_SOURCE_DATABASE_NAME=production16
OPENUPGRADE_TARGET_DATABASE_NAME=migration17
```

Both source and target are currently expected to live on the same PostgreSQL endpoint configured by `DB_HOST` / `DB_PORT`:

```text
Migration VM                         PostgreSQL VM
Docker / OpenUpgrade                10.20.0.15:5432
+----------------------+            +----------------------+
| pg_dump / pg_restore |----------->| production16         |
| Odoo target version  |            | migration17          |
+----------------------+            +----------------------+
```

The migration VM must be able to reach TCP port `5432` on the PostgreSQL VM. A simple connectivity check from the migration host is:

```bash
nc -zv 10.20.0.15 5432
```

On the PostgreSQL server, `listen_addresses` must allow the required interface and `pg_hba.conf` must allow the migration VM address. Prefer a specific address or subnet, for example:

```conf
host    all    odoo_migration    10.20.0.25/32    scram-sha-256
```

Do not expose PostgreSQL to `0.0.0.0/0` unless that is explicitly required and protected by the surrounding network/firewall policy.

The role configured by `DB_USER` must be able to:

- connect to and read the source database for `pg_dump`;
- create a target database (`CREATEDB` or equivalent permission);
- restore schema/data into the target;
- drop the target when `OPENUPGRADE_RECREATE_DATABASE=True`.

Example administrative preparation:

```sql
ALTER ROLE odoo_migration CREATEDB;
```

Grant only the additional source-database read permissions that are required by your PostgreSQL ownership/ACL model.

The bundled Compose `db` service may still start as a dependency of `docker compose run`, but migration connections use `DB_HOST`. If `DB_HOST` points to another VM, the OpenUpgrade SQL traffic goes to that external PostgreSQL server.

### External filestore / another Odoo VM

PostgreSQL cloning does not clone the Odoo filestore. The filestore normally lives on the Odoo application host, not on the PostgreSQL VM.

For example:

```text
Old Odoo VM                          Migration VM
/var/lib/odoo/filestore/odoo16  ->  /var/lib/odoo/filestore/odoo16
                                         |
                                         +-> copied to filestore/odoo17
```

If the source filestore is on another VM, copy it to the migration host before `make migrate`, for example with `rsync`:

```bash
rsync -a \
  odoo@old-odoo-vm:/var/lib/odoo/filestore/production16/ \
  /path/to/migration-odoo-data/filestore/production16/
```

The source filestore must be visible inside the migration container as:

```text
${DATA_DIR}/filestore/${OPENUPGRADE_SOURCE_DATABASE_NAME}
```

With:

```env
OPENUPGRADE_COPY_FILESTORE=True
```

the entrypoint copies it to the target filestore directory before OpenUpgrade validation. If the source filestore is not visible, the migration continues with a warning, but attachments/documents/images cannot be fully validated until the filestore is provided.

### Existing target database safety

The target database is not overwritten by default.

If the target exists and contains a matching successful migration marker, the migration is skipped.

If the target exists without that marker, migration stops with an error. This includes a database left by a failed/partial migration.

To intentionally discard the target and rebuild it from source:

```env
OPENUPGRADE_RECREATE_DATABASE=True
```

Then rerun:

```bash
make migrate
```

This drops only `OPENUPGRADE_TARGET_DATABASE_NAME`, creates it again from the source, and retries the migration. Never use the same name for source and target.

`OPENUPGRADE_FORCE=True` is intended only for an explicit re-run on an already completed target. Normally it should remain `False`; for a clean retry after a failed migration use `OPENUPGRADE_RECREATE_DATABASE=True` instead.

### Custom migration scripts

Custom/OCA addons must have code compatible with the target Odoo version before the migration is attempted.

Module-local upgrade scripts should live in the addon itself, for example:

```text
my_module/
  migrations/
    18.0.1.0.0/
      pre-migration.py
      post-migration.py
```

or the equivalent Odoo `upgrades/` directory supported by the target version.

For project-wide external scripts use the configured upgrade path, for example:

```env
UPGRADE_PATH=/opt/local-addons/upgrade
```

All installed modules in the source database must be available in compatible form in the target image. Before a real migration it is useful to inspect the installed module list:

```sql
SELECT name, latest_version
FROM ir_module_module
WHERE state = 'installed'
ORDER BY name;
```

### Recommended migration procedure

For each hop:

1. checkout the target major-version branch;
2. copy `openupgrade.env.example` to a dedicated env file and fill in PostgreSQL credentials, source and target database names;
3. if PostgreSQL is on another VM, verify `DB_HOST`, firewall, `pg_hba.conf`, credentials and `CREATEDB` permission;
4. if the filestore is on another VM, copy or mount the source filestore into the migration host/container;
5. build the target image with `make init ENV_FILE=<migration-env>`;
6. run the one-shot migration with `make migrate ENV_FILE=<migration-env>`;
7. if migration fails, inspect the error; for a clean retry set `OPENUPGRADE_RECREATE_DATABASE=True` and rerun `make migrate`;
8. after success run `make up ENV_FILE=<migration-env>` and functionally validate the migrated Odoo instance;
9. use that successful target database as the source for the next major-version hop.

Example `16 -> 17`:

```bash
git switch 17.0
cp openupgrade.env.example .env.migrate-17
# edit .env.migrate-17
make init ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
make migrate ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
make up ENV_FILE=.env.migrate-17 COMPOSE_PROJECT_NAME=odoo-migrate-17
```

Example `17 -> 18`:

```bash
git switch agent/openupgrade-18
cp openupgrade.env.example .env.migrate-18
# edit .env.migrate-18: source=odoo17, target=odoo18
make init ENV_FILE=.env.migrate-18 COMPOSE_PROJECT_NAME=odoo-migrate-18
make migrate ENV_FILE=.env.migrate-18 COMPOSE_PROJECT_NAME=odoo-migrate-18
make up ENV_FILE=.env.migrate-18 COMPOSE_PROJECT_NAME=odoo-migrate-18
```

Example `18 -> 19`:

```bash
git switch agent/openupgrade-19
cp openupgrade.env.example .env.migrate-19
# edit .env.migrate-19: source=odoo18, target=odoo19
make init ENV_FILE=.env.migrate-19 COMPOSE_PROJECT_NAME=odoo-migrate-19
make migrate ENV_FILE=.env.migrate-19 COMPOSE_PROJECT_NAME=odoo-migrate-19
make up ENV_FILE=.env.migrate-19 COMPOSE_PROJECT_NAME=odoo-migrate-19
```

Do not continue to the next major version from a database whose current hop has not been validated.

## Runtime configuration

`.env` is mounted into the container as `/run/odoo/.env`. `/etc/odoo.conf` is rendered by `base/scripts/odoorc.py` from `base/config/odoo.conf.tpl`.

Use `ODOO_EXTRA_OPTS` for Odoo config entries that are not exposed as dedicated environment variables.

Default service topology:

- Caddy: public ports `80/443`
- Odoo HTTP: internal `8069`
- Odoo gevent/websocket: internal `8072`
- PostgreSQL: internal `5432` when the bundled DB is used
- Redis: internal `6379`
- `kwkhtmltopdf`: internal `8080`

Persistent data:

- PostgreSQL: `db-data`
- Odoo data/filestore: `odoo-data`
- Redis: `redis-data`
- Caddy: `caddy-data`, `caddy-config`

## Backup and restore

Create a backup:

```bash
make backup
make backup NAME=before-upgrade
```

The backup contains the PostgreSQL dump, filestore archive, and manifest under `backups/<name>/`.

Restore:

```bash
make restore BACKUP=backups/<name>
```

A restore overwrites the configured `DB_NAME` database and corresponding filestore, so verify the target environment before running it.

## Security

- do not commit `.env`;
- replace all `CHANGE_ME_*` values;
- keep PostgreSQL and Redis private unless explicitly required;
- do not store production backups in Git;
- use a strong Odoo master password;
- test migrations on copies, never directly on the production database.

## References

- [OCA/OpenUpgrade](https://github.com/OCA/OpenUpgrade)
- [git-aggregator](https://github.com/acsone/git-aggregator)
- [Docker Compose CLI](https://docs.docker.com/engine/reference/commandline/compose/)
- [Caddy](https://caddyserver.com/docs/)
- [kwkhtmltopdf](https://github.com/acsone/kwkhtmltopdf)
