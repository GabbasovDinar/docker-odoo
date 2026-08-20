# docker-odoo

[`docker-odoo`](https://github.com/GabbasovDinar/docker-odoo) is a Docker Compose project for building and running Odoo from source with custom addons. It uses a two-stage image build, PostgreSQL, Redis-backed sessions, internal `kwkhtmltopdf`, and Caddy as the public entrypoint. Odoo core is installed in the `base/` image, extra addon repositories are pulled during the `addons/` image build, local modules are mounted from `local-addons/`, and runtime configuration is generated from `.env` into `/etc/odoo.conf`.

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

- `GITHUB_TOKEN`, `GITLAB_TOKEN`, `GIT_TOKEN` for private Odoo source or addon repositories
- `ODOO_EE_GIT_TOKEN` for Odoo Enterprise builds

## Minimum Setup

Copy the example env file:

```bash
cp .env.example .env
```

Set `ODOO_VERSION` to the checked-out branch version. For example, on branch `18.0`:

```env
ODOO_VERSION=18.0
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
- `make up` starts the stack in the normal runtime mode.
- `make prod` is an explicit alias for the normal production-mode startup (`make up`).
- `make dev` starts the stack in development mode with `debugpy`, Odoo development helpers and zero workers.
- `make test` runs tests for installable modules under `local-addons/` in one-shot test mode.
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
make migrate ENV_FILE=.env.migrate-18 COMPOSE_PROJECT_NAME=odoo-migrate-18
```

## Runtime Modes

Use explicit mode shortcuts when you want the command itself to communicate intent:

```bash
make prod
make dev
make test
```

`make prod` is equivalent to the normal `make up` startup and uses only `docker-compose.yml` with `MODE=prod`.

## Development Mode and Debugging

Development mode is opt-in and editor/IDE agnostic. It uses `docker-compose.dev.yml` in addition to the normal Compose file. Production behavior is unchanged and the debug port is not published unless development mode is selected.

The dev runtime enables:

- `debugpy` on TCP port `5678` by default;
- Odoo `--dev=all` by default;
- Odoo `debug` logging by default;
- `--workers=0` so requests stay in the process attached to the debugger;
- a loopback-only host mapping for the debug port: `127.0.0.1:5678`;
- local addons mounted from `local-addons/` to `/opt/local-addons` inside the container.

After pulling these changes, rebuild the base image once because `debugpy` is installed into the image:

```bash
make init
```

Start the normal runtime as before:

```bash
make up
```

Start development mode with the dedicated shortcut:

```bash
make dev
```

This is equivalent to:

```bash
make up MODE=dev
```

Development mode overrides the normal `LOG_LEVEL` with `DEV_LOG_LEVEL`, which defaults to `debug`. Override it when a quieter or more detailed session is needed:

```bash
DEV_LOG_LEVEL=info make dev
DEV_LOG_LEVEL=debug_sql make dev
```

Additional Make variables can be passed to `make dev` normally:

```bash
make dev ENV_FILE=.env.local COMPOSE_PROJECT_NAME=docker-odoo-dev
```

Check the resolved Compose files with:

```bash
make env MODE=dev
```

The output should include both:

```text
-f docker-compose.yml -f docker-compose.dev.yml
```

Follow Odoo logs:

```bash
make log-odoo MODE=dev
```

When debugpy is ready, Odoo logs:

```text
[debugpy] listening on 0.0.0.0:5678
```

### Attaching a debugger

Any Python debugger client that supports attaching to `debugpy` can be used. Configure the client with:

```text
host: 127.0.0.1
port: 5678
```

For source mapping, local custom addons correspond to:

```text
local:  <repository>/local-addons
remote: /opt/local-addons
```

The repository includes `.vscode/launch.json` and `.vscode/extensions.json` as a ready-to-use VS Code/Cursor example. They are not required by the runtime and can be ignored when using another editor or IDE.

The example configuration uses `justMyCode: false`, which allows stepping from custom modules into Odoo core and other Python code.

Breakpoints can be added or removed before or after the debugger attaches. A breakpoint only affects future execution of that line; if a request already passed the line, trigger the code path again.

### Debugging startup code

By default Odoo starts immediately and a debugger can attach later. To stop before Odoo initialization and wait for the debugger client:

```bash
DEBUGPY_WAIT_FOR_CLIENT=1 make dev
```

The log will show:

```text
[debugpy] waiting for debugger client...
```

Attach the debugger to `127.0.0.1:5678`; Odoo startup then continues. This is useful for module imports, registry initialization, hooks and other startup-only code.

While `DEBUGPY_WAIT_FOR_CLIENT=1` is active, the Odoo healthcheck remains unhealthy until the debugger connects because the HTTP server has not started yet.

### Odoo autoreload and debugger reconnects

Development mode defaults to `DEV_MODE=all`. Odoo's dev mode includes Python autoreload. When a watched Python file changes, Odoo re-executes itself. The custom debug bootstrap remains the Python entry script, so debugpy starts again after the re-exec instead of disappearing permanently.

The current debugger connection can still disconnect during that re-exec. Attach again to the new process when needed.

For a more stable step-debugging session, disable Odoo Python autoreload while keeping the other useful development helpers:

```bash
DEV_MODE=xml,qweb,access make dev
```

After changing Python code in this mode, restart Odoo explicitly and attach again:

```bash
make restart MODE=dev
```

### Changing the debug port

Override the port if `5678` is already in use:

```bash
DEBUGPY_PORT=5679 make dev
```

Configure the debugger client to use the same port.

The dev Compose file publishes debugpy only on `127.0.0.1`. Do not publish the debug adapter on a public interface.

### Odoo shell in dev mode

`make odoo-shell MODE=dev` continues to run as a normal Odoo shell and does not try to open another debugpy listener. This avoids a port collision with the already running debug server.

## Test Mode

Test mode is a one-shot Odoo test runner for addons mounted under `local-addons/`. It is based on the same two-phase idea used by OCA CI: dependencies are installed first without running their tests, then the selected local addons are installed with Odoo's native test runner enabled.

Test mode uses `docker-compose.test.yml` and `MODE=test`. The public entrypoint is:

```bash
make test
```

Unlike `make up` and `make dev`, `make test` does not start a long-running Odoo service. It starts a disposable Odoo container, returns Odoo's test exit code, and removes the container when the run finishes.

Test mode uses Odoo `info` logging by default. Override it with `TEST_LOG_LEVEL` when investigating a failure:

```bash
TEST_LOG_LEVEL=debug make test
TEST_LOG_LEVEL=debug_sql make test TEST_MODULES=my_sale
```

After pulling test-mode changes, rebuild the image once so the test runner is available:

```bash
make init
```

Check the resolved test Compose configuration with:

```bash
make env MODE=test
```

The output includes:

```text
-f docker-compose.yml -f docker-compose.test.yml
```

### Default clean-database run

With no test parameters:

```bash
make test
```

the runner:

1. uses `manifestoo` to find every installable addon under `/opt/local-addons`;
2. resolves their declared Odoo dependencies;
3. creates a uniquely named empty PostgreSQL database such as `odoo_test_20260819_123456_12345`;
4. initializes the database and installs dependencies with demo data disabled and tests disabled;
5. installs the selected local addons with `--test-enable` so Odoo runs their `at_install` and `post_install` tests;
6. runs with zero workers and zero cron workers, then exits with the Odoo test status;
7. drops the generated database and its filestore when the run succeeds.

This separation is intentional: dependency modules are needed for installation, but the default goal is to test the project modules from `local-addons/`, not every dependency's own test suite.

If no installable addon is found under `local-addons/`, the command exits successfully without creating a database.

### Failed test database lifecycle

A generated test database is deleted automatically only after a successful run.

If installation or tests fail, the generated database is preserved for inspection and its name is printed. The next plain:

```bash
make test
```

still creates a new clean database. This is the recommended way to reproduce a failure because every normal run starts from the same clean state instead of inheriting mutations from a failed run.

When useful for investigation, run against the preserved database explicitly:

```bash
make test TEST_DB=odoo_test_20260819_123456_12345
```

A preserved database may represent a partially failed installation, so reuse is primarily a debugging tool; use a fresh run for reproducibility.

To preserve even successful generated databases:

```bash
make test TEST_KEEP_DB=1
```

To always remove a generated database after a failed run:

```bash
make test TEST_DROP_FAILED_DB=1
```

### Run only specific local modules

Use `TEST_MODULES` to limit which addons from `local-addons/` are installed and tested:

```bash
make test TEST_MODULES=my_sale,my_stock
```

`TEST_MODULES` is a comma-separated list. Every requested name must be an installable addon found under `local-addons/`. Dependencies are still resolved and installed automatically.

Use `TEST_MODULES` when you want to reduce the installation scope. Use `TEST_TAGS` when you want to filter which tests Odoo executes.

### Odoo test tags

`TEST_TAGS` is passed directly to Odoo's `--test-tags` option, so normal Odoo test selectors can be used.

Test one module:

```bash
make test TEST_TAGS='/my_sale'
```

Combine Odoo tags:

```bash
make test TEST_TAGS='standard,-slow'
```

Select a class or method:

```bash
make test TEST_TAGS='/my_sale:TestSale.test_confirm'
```

Limit both installation and test selection:

```bash
make test \
  TEST_MODULES=my_sale \
  TEST_TAGS='/my_sale:TestSale.test_confirm'
```

When only `TEST_TAGS` is specified on a clean run, all local addons are still installed; the tags filter test execution. Add `TEST_MODULES` as well when installation should also be limited.

### Additional Odoo test arguments

Pass additional Odoo CLI options with `ARGS`. For example:

```bash
make test ARGS='--test-file=/opt/local-addons/my_sale/tests/test_sale.py'
```

For logging verbosity prefer the mode-specific variable instead of passing `--log-level` through `ARGS`:

```bash
TEST_LOG_LEVEL=debug make test
```

The runner itself owns the database, module installation, zero-worker and stop-after-init options. `ARGS` is intended for additional Odoo test/logging options rather than replacing those lifecycle controls.

### Run tests on an existing database

To run tests against an existing database:

```bash
make test TEST_DB=my_test_database
```

For an already initialized Odoo database, test mode does not install or upgrade modules. It finds which selected local addons are already installed and runs their tests using Odoo module test-tag selectors. If `TEST_TAGS` is provided, that expression is passed to Odoo instead.

To require a specific installed local addon:

```bash
make test \
  TEST_DB=my_test_database \
  TEST_MODULES=my_sale
```

If an addon explicitly listed in `TEST_MODULES` is not installed in that database, the command fails instead of modifying the database automatically.

If `TEST_DB` exists but is an empty, uninitialized PostgreSQL database, the normal initialization/install/test flow is used, but the explicitly supplied database is never deleted automatically.

Testing an existing database is not isolated. Do not point this mode at a production database; use a disposable copy or a dedicated test/staging database.

### External PostgreSQL

The default clean test mode must be able to create and drop temporary databases. When `DB_HOST` points to an external PostgreSQL server, the configured `DB_USER` therefore needs `CREATEDB` (or equivalent database-management privileges):

```sql
ALTER ROLE odoo CREATEDB;
```

When `TEST_DB` points to an existing initialized database, automatic database creation and deletion are not used.

## Odoo Source and CE / EE

The base image fetches the Odoo Community source with normal Git using an explicit shallow fetch (`git fetch --depth=1 --no-tags`). The source repository and revision are independent from the Docker image tag, so the build can use the official upstream repository, a fork, a self-hosted GitLab repository, a branch, a tag, or a pinned commit without changing `base/Dockerfile`.

The default configuration builds Odoo 18 from the official GitHub repository:

```env
ODOO_EDITION=ce
ODOO_VERSION=18.0
ODOO_REPO=https://github.com/odoo/odoo.git
ODOO_BRANCH=${ODOO_VERSION}
ODOO_REF=
```

Source selection uses this order:

1. `ODOO_REF` when it is non-empty;
2. `ODOO_BRANCH` when `ODOO_REF` is empty;
3. `ODOO_VERSION` as the final default.

`ODOO_CE_REF` and `ODOO_CE_VERSION` are still accepted by `docker-compose.yml` as compatibility fallbacks for older env files, but new configurations should use `ODOO_REPO`, `ODOO_BRANCH`, and `ODOO_REF`.

### Use another public Odoo repository

For example, to build from a self-hosted public GitLab fork:

```env
ODOO_REPO=https://gitlab.my.com/odoo-project/odoo.git
ODOO_BRANCH=18.0
ODOO_REF=
```

Then rebuild the base and project images:

```bash
make init
```

The selected checkout becomes `/opt/odoo`. Odoo Python requirements are installed from `/opt/odoo/requirements.txt`, so source code and requirements always come from the same revision. Git metadata is removed after checkout because the runtime image does not need repository history.

### Pin Odoo to a commit

For reproducible builds, set `ODOO_REF` to the full 40-character Git commit SHA:

```env
ODOO_REPO=https://gitlab.my.com/odoo-project/odoo.git
ODOO_BRANCH=18.0
ODOO_REF=0123456789abcdef0123456789abcdef01234567
```

A pinned `ODOO_REF` overrides `ODOO_BRANCH`. Clear `ODOO_REF` to follow the configured branch again. A full commit SHA is recommended for an immutable production build; branches and tags remain supported for normal development and release workflows.

Rebuild after changing the source repository or ref:

```bash
make build-base
make build-addons
```

or simply:

```bash
make init
```

### Private Odoo repository over HTTPS

Odoo source authentication now uses the same mechanism as private addon repositories. The build mounts `GITHUB_TOKEN`, `GITLAB_TOKEN`, and `GIT_TOKEN` as BuildKit secrets. The source helper creates a temporary `~/.netrc`, performs the shallow Git fetch, and removes the `.netrc` before the build step finishes. Tokens are not passed as Dockerfile build arguments or persisted in image layers.

For a private self-hosted GitLab repository using a Personal Access Token or Project Access Token:

```env
ODOO_REPO=https://gitlab.my.com/odoo-project/odoo.git
ODOO_BRANCH=18.0
ODOO_REF=0123456789abcdef0123456789abcdef01234567

GITLAB_HOST=gitlab.my.com
GITLAB_USER=oauth2
GITLAB_TOKEN=glpat-xxxxxxxxxxxxxxxx
```

For GitLab Personal Access Tokens and Project Access Tokens the username only needs to be non-empty, so the default `oauth2` value is suitable. Give the token only the repository access required by the build, normally `read_repository`.

If a credential requires a specific username, put that username in `GITLAB_USER`. For example, a deploy token can use:

```env
GITLAB_HOST=gitlab.my.com
GITLAB_USER=gitlab+deploy-token-123
GITLAB_TOKEN=YOUR_DEPLOY_TOKEN
```

A GitLab CI job token can use:

```env
GITLAB_HOST=gitlab.my.com
GITLAB_USER=gitlab-ci-token
GITLAB_TOKEN=${CI_JOB_TOKEN}
```

For a private GitHub repository:

```env
ODOO_REPO=https://github.com/my-company/odoo.git
GITHUB_HOST=github.com
GITHUB_USER=x-access-token
GITHUB_TOKEN=github_pat_xxxxxxxxxxxxxxxx
```

For another HTTPS Git host, use the generic credentials:

```env
ODOO_REPO=https://git.example.com/odoo/odoo.git
GIT_HOST=git.example.com
GIT_USER=oauth2
GIT_TOKEN=xxxxxxxxxxxxxxxx
```

The same `GITHUB_*`, `GITLAB_*`, and generic `GIT_*` credentials are also available to the addon repository build, so there is no separate Odoo Community authentication configuration anymore. The local `.env` still contains secret values and must never be committed.

SSH agent/key forwarding is intentionally not configured for the Odoo Community source flow in this project. Use an HTTPS repository URL when the source repository is private.

### Enterprise Edition

Enterprise mode uses the same configurable Community/core source described above, then installs Enterprise addons separately from `ODOO_ENTERPRISE_REPO`.

```env
ODOO_EDITION=ee
ODOO_VERSION=18.0
ODOO_REPO=https://github.com/odoo/odoo.git
ODOO_BRANCH=18.0
ODOO_REF=
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
- For reproducible Community/core builds, pin `ODOO_REF` to the required full commit SHA.
- For reproducible Enterprise builds, set `ODOO_ENTERPRISE_REF` to the required branch, tag, or commit.
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

Example for `17.0 -> 18.0`:

```env
ODOO_VERSION=18.0
OPENUPGRADE=True
OPENUPGRADE_SOURCE_DATABASE_NAME=ODOO_17
OPENUPGRADE_TARGET_DATABASE_NAME=ODOO_18
OPENUPGRADE_TARGET_VERSION=18.0
OPENUPGRADE_RECREATE_DATABASE=False
OPENUPGRADE_FORCE=False
OPENUPGRADE_COPY_FILESTORE=True
```

The result is:

```text
ODOO_17    unchanged source database
ODOO_18    copy of ODOO_17, migrated to Odoo 18
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
OPENUPGRADE_SOURCE_DATABASE_NAME=production17
OPENUPGRADE_TARGET_DATABASE_NAME=migration18
```

Current source-to-target cloning expects both databases to be on the same configured PostgreSQL endpoint:

```text
Migration VM                         PostgreSQL VM
Docker / OpenUpgrade                10.20.0.15:5432
+----------------------+            +----------------------+
| pg_dump / pg_restore |----------->| production17         |
| Odoo target version  |            | migration18          |
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
  odoo@old-odoo-vm:/var/lib/odoo/filestore/production17/ \
  /path/to/source-filestore/production17/
```

Then ensure that the content is available inside the migration container as:

```text
/var/lib/odoo/filestore/production17
```

If the source filestore is not visible, the entrypoint logs a warning and continues with the database migration. Attachments, documents, images, and other filestore-backed records cannot be fully validated until the filestore is available.

### Custom Migration Scripts

All installed custom/OCA addons from the source database must have code compatible with the target Odoo version before migration.

Module-local migration scripts should live in the addon itself, for example:

```text
my_module/
  migrations/
    18.0.1.0.0/
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

Example `17 -> 18`:

```bash
git switch 18.0
cp openupgrade.env.example .env.migrate-18
# edit .env.migrate-18
make init ENV_FILE=.env.migrate-18 COMPOSE_PROJECT_NAME=odoo-migrate-18
make migrate ENV_FILE=.env.migrate-18 COMPOSE_PROJECT_NAME=odoo-migrate-18
make up ENV_FILE=.env.migrate-18 COMPOSE_PROJECT_NAME=odoo-migrate-18
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

- [Odoo 18 documentation](https://www.odoo.com/documentation/18.0/)
- [Odoo 18 testing documentation](https://www.odoo.com/documentation/18.0/developer/reference/backend/testing.html)
- [Git fetch documentation](https://git-scm.com/docs/git-fetch)
- [Docker build secrets](https://docs.docker.com/build/building/secrets/)
- [OCA/oca-ci](https://github.com/OCA/oca-ci)
- [manifestoo](https://github.com/acsone/manifestoo)
- [OCA/OpenUpgrade](https://github.com/OCA/OpenUpgrade)
- [git-aggregator](https://github.com/acsone/git-aggregator)
- [Docker Compose CLI reference](https://docs.docker.com/engine/reference/commandline/compose/)
- [Caddy documentation](https://caddyserver.com/docs/)
- [kwkhtmltopdf](https://github.com/acsone/kwkhtmltopdf)
