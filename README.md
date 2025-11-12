# docker-odoo

Two-stage Docker setup for Odoo 18. The `base/` Dockerfile builds a reusable
runtime with wkhtmltopdf, PostgreSQL tooling and helper scripts. The
`addons/` Dockerfile consumes that image, pulls the repositories declared in
`addons/addons.yml` and installs extra Python dependencies so the resulting
image can run Odoo with your custom modules baked in.

## Repository layout

```
.
├── base/
│   ├── Dockerfile              # builds the core Odoo image
│   ├── config/odoo.conf.tpl    # template rendered on container start
│   ├── manifests/enterprise.yml
│   └── scripts/                # entrypoint + helper utilities
├── addons/
│   ├── Dockerfile              # builds the addons layer
│   ├── addons.yml              # git-aggregator configuration
│   └── requirements.txt        # extra Python dependencies installed at build time
├── docker-compose.yml          # example stack (Odoo + PostgreSQL + wkhtmltopdf)
├── makefile                    # quality-of-life commands
├── .env.example                # template for environment variables
```

## Quickstart

```bash
cp .env.example .env
make build        # build odoo-core-* and odoo-* images
make up           # start postgres + odoo in the background
make logs         # tail the Odoo logs
```

All Make targets read from the `.env` file in the project root. The Compose file
mounts the same `.env` into the container at `/run/odoo/.env`; restarting the
services is enough to pick up configuration changes.

If you prefer raw Docker Compose commands you can reproduce the Makefile
behaviour manually:

```bash
# Build both images
docker compose -f docker-compose.yml --profile build build odoo-core
ODOO_EDITION=ce docker compose -f docker-compose.yml build odoo

# Start the stack
docker compose -f docker-compose.yml up -d --build
```

## Building images

The Makefile exposes common combinations so you do not have to remember full
Compose invocations:

* `make build-base` — build only the reusable core image (`odoo-core-*`).
* `make build-addons` — build only the project addons image (`odoo-*`).
* `make build` — build both stages.
* `make rebuild-addons` — rebuild the addons stage without cache.
* `make build-ce` / `make build-ee` — convenience aliases that set
  `ODOO_EDITION` for Community or Enterprise.

Enterprise builds require valid credentials for the private `odoo/enterprise`
repository. Populate the token variables in `.env` and use `make build-ee` (or
set `ODOO_EDITION=ee` when running `make build-base` / `make build-addons`).

## Running the stack

Useful targets for day-to-day operations:

* `make up`, `make start` — start all services in detached mode.
* `make stop` — stop services without removing containers.
* `make restart` — restart the running services.
* `make down` — stop and remove containers (named volumes remain).
* `make down-v` — stop services and remove containers, networks and volumes.
* `make logs`, `make logs-db` — follow the Odoo or PostgreSQL logs.
* `make sh` — open an interactive shell in the Odoo container.
* `make psql` — open a `psql` session against PostgreSQL.
* `make config` — print the rendered Compose configuration.

The stack exposes Odoo on port 8069 by default. Adjust the port mapping inside
`docker-compose.yml` if you need a different host port.

## Environment configuration

1. Copy `.env.example` to `.env` and edit the values that matter for your
   project.
2. Every Make target and Compose build reads from `.env`; the file is also
   mounted into the container at `/run/odoo/.env` before rendering
   `odoo.conf`.
3. The template is grouped into themed sections and documents every variable
   referenced by [`base/config/odoo.conf.tpl`](base/config/odoo.conf.tpl).

### Essential settings

The first block in `.env.example` contains the bare minimum to get a stack up:

* `ODOO_VERSION`, `ODOO_EDITION` — pin the upstream release and choose between
  Community or Enterprise images.
* `ADMIN_PASSWORD` — master password required for database management inside
  Odoo.
* `LIST_DB`, `DBFILTER` — control whether the login page lists databases and
  how to filter them.
* `WORKERS` — set to `0` for the threaded server or a positive integer when
  fronted by a reverse proxy.

### Database connection

`DB_PASSWORD` and the `DATABASE_NAME`/`DB_NAME` pair drive the PostgreSQL
connection for both build-time and runtime containers. If you rotate
`DB_PASSWORD`, remove the `db-data` volume (for example with
`docker compose down -v`) so PostgreSQL forgets the previous credentials.
The same section exposes `DB_USER`, `DB_HOST`, `DB_PORT` and advanced knobs such
as `DB_MAXCONN` and `DB_TEMPLATE`.

### Additional sections

The remaining groups unlock optional behaviour:

* **Build context & filesystem paths** — adjust `ADDONS_YML`,
  `LOCAL_ADDONS_DIR`, or the generated `ODOO_RC` path.
* **Module loading & demo data** — toggle `INIT`, `UPDATE`, demo fixtures,
  `ODOO_EXTRA_OPTS`, and reporting settings like `REPORT_URL`.
* **HTTP, proxy & realtime** — map ports, enable `PROXY_MODE`, or fine-tune
  websocket rate limits.
* **Logging & diagnostics / Email / Internationalisation** — configure
  telemetry, SMTP, translations, and log destinations.
* **Enterprise edition options** — point Odoo at private Enterprise repositories
  when running with `ODOO_EDITION=ee`.

Every variable ships with a comment describing its intent, so you can skim the
template to discover lesser-used switches as your deployment grows.

## Mounting local addons

Any directory pointed to by `LOCAL_ADDONS_DIR` is mounted inside the container at
`/opt/local-addons` and appended to `ADDONS_PATH`. By default the repository
ships an empty `local-addons/` folder that you can populate with custom modules
without rebuilding images.

```bash
mkdir -p local-addons
# (optional) echo "LOCAL_ADDONS_DIR=/absolute/path" >> .env
make restart
```

Modules dropped into that directory become available after a restart.

## Updating addons

Edit `addons/addons.yml` to add/remove repositories. The manifest is processed by
`extra-addons.sh`, which understands the [git-aggregator](https://github.com/acsone/git-aggregator)
syntax. After editing the manifest rerun `make rebuild-addons` to bake the new
modules into the image.

## Troubleshooting

* `make psql` is useful for checking database connectivity when Odoo fails to
  start.
* `make down-v` removes both Postgres and Odoo volumes, which is required if you
  change database credentials.
* Logs from the Odoo container already include the rendered configuration path:
  `/etc/odoo.conf`.

## References

* [Odoo 18 documentation](https://www.odoo.com/documentation/18.0/)
* [git-aggregator](https://github.com/acsone/git-aggregator)
* [Docker Compose CLI reference](https://docs.docker.com/engine/reference/commandline/compose/)
