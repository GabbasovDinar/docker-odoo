# docker-odoo

Two-stage Docker setup for Odoo 18.0. The first stage builds a reusable core
image with Odoo, wkhtmltopdf and helper tooling. The second stage consumes an
`addons.yml` manifest, aggregates external repositories with
[git-aggregator](https://github.com/acsone/git-aggregator), installs Python and
Debian dependencies via [manifestoo](https://manifestoo.readthedocs.io/), and
bakes the collected addons into the final runtime image.

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
└── TODO.md
```

## Quickstart

```bash
cp .env.example .env
make build            # build base + addons images (Community Edition by default)
make up               # start the stack
make logs             # follow the Odoo logs
```

All Make targets read from the `.env` file in the project root. The Compose file
mounts the same `.env` into the containers so configuration changes are applied
on the next restart.

## Building images

### Using the Makefile

* `make build-base` — build only the reusable core image (`odoo-core`).
* `make build-addons` — build only the addons image (`odoo`).
* `make build` — build both layers in sequence.
* `make rebuild-addons` — rebuild the addons image without using any cached
  layers (`docker compose build --no-cache`).

Community Edition (`ce`) is the default. To build Enterprise Edition images you
need valid credentials for the private Enterprise repository. Populate the
GitHub/GitLab token variables in `.env` and run one of the following:

```bash
make build-ee            # build core + addons with ODOO_EDITION=ee
# or
ODOO_EDITION=ee make build-base
ODOO_EDITION=ee make build-addons
```

### Using Docker Compose directly

```bash
# Build the core image
ODOO_EDITION=ce docker compose --profile build build odoo-core

# Build the addons layer
ODOO_EDITION=ce docker compose build odoo
```

For Enterprise Edition, export `ODOO_EDITION=ee` and ensure the Enterprise
repository variables in `.env` point to a source you can access.

## Running the stack

### With the Makefile

* `make up` — start the full stack (`docker compose up -d --build`).
* `make start` — alias for `make up`.
* `make stop` — stop services without removing resources.
* `make restart` — restart all services.
* `make down` — stop services and remove containers (keeps named volumes).
* `make down-v` — stop services and remove containers, networks and volumes.
* `make ps` — show Compose service status.
* `make logs` — tail the Odoo logs.
* `make logs-db` — tail the PostgreSQL logs.
* `make sh` — open an interactive shell inside the Odoo container.
* `make psql` — connect to PostgreSQL using `psql`.
* `make config` — print the fully-rendered Compose configuration.
* `make prune` — prune the local Docker builder cache.

### With Docker Compose

```bash
# Start the stack
docker compose up -d --build

# Stop or tear down services
docker compose stop
docker compose down --remove-orphans

# Inspect logs
docker compose logs -f --tail=200 odoo
```

## Managing environment variables

1. Copy `.env.example` to `.env` and adjust the values to fit your environment.
2. The `.env` file is mounted into build and runtime containers at
   `/run/odoo/.env`. Updating it and restarting the stack is enough to apply new
   settings.
3. Key parameters:
   * `ODOO_VERSION` — target Odoo version tag (defaults to 18.0).
   * `ODOO_EDITION` — either `ce` or `ee`; controls which images and manifests
     are used.
   * `ODOO_HOST_PORT` — host port that forwards to Odoo's 8069.
   * `DB_*` variables — connection details for PostgreSQL.
   * `SMTP_*`, `REPORT_URL` — outbound services for email and PDF rendering.
   * `GITHUB_TOKEN`, `GITLAB_TOKEN` — authentication tokens used by
     `git-aggregator` during the image build (leave empty if all repositories
     are public).
   * `LOCAL_ADDONS_DIR` — host directory with custom modules to overlay at runtime
     (defaults to `./local-addons`).

## Mounting local addons

Use `LOCAL_ADDONS_DIR` to expose custom modules without baking them into the
image. The directory is mounted into the Odoo container at `/opt/local-addons`
and is appended to the default `ADDONS_PATH`.

```bash
# 1. Create the directory on the host
mkdir -p local-addons

# 2. Point the environment variable at it (optional if you keep the default)
echo "LOCAL_ADDONS_DIR=./local-addons" >> .env

# 3. Restart the stack so the mount is picked up
make restart
```

Any modules placed inside `local-addons/` are immediately available to Odoo. The
volume can point to any absolute or relative path if you prefer to keep custom
code elsewhere; just adjust `LOCAL_ADDONS_DIR` accordingly.

### Extra Odoo options

The `ODOO_EXTRA_OPTS` variable is appended verbatim to the rendered `odoo.conf`.
Use it to inject additional sections without editing the template. Multiline
values must be quoted. Example for enabling the OCA `queue_job` module with two
worker channels:

```ini
ODOO_EXTRA_OPTS="
[queue_job]
channels = root:2
"
```

On container start the entrypoint regenerates `/etc/odoo.conf` with the latest
contents of `.env`, so no manual edits to the file are necessary.

## Adding new addon repositories

1. Edit `addons/addons.yml` and add another entry. A minimal GitHub example:

   ```yaml
   ./oca-queue:
     remotes:
       origin: https://github.com/OCA/queue.git
     merges:
       - remote: origin
         ref: "18.0"
         depth: 1
     target: oca-queue
   ```

2. If the repository is private, set the appropriate token variables in `.env`
   (`GITHUB_TOKEN`, `GITLAB_TOKEN`, etc.). They are read by `extra-addons.sh`
   when Docker builds the image.
3. Rebuild the addons image:

   ```bash
   make rebuild-addons
   ```

4. The aggregated addons end up under `/opt/extra-addons` inside the runtime
   container. Mount `local-addons/` for custom modules that should not be baked
   into the image.

## References

* [Odoo 18 documentation](https://www.odoo.com/documentation/18.0/)
* [git-aggregator](https://github.com/acsone/git-aggregator)
* [Manifestoo CLI](https://manifestoo.readthedocs.io/)
* [Docker Compose CLI reference](https://docs.docker.com/engine/reference/commandline/compose/)
* [Odoo queue_job module](https://github.com/OCA/queue/tree/18.0/queue_job)

## Disclaimer & support

Use this setup at your own risk. The stack can evolve quickly, and there may be
undiscovered bugs or edge cases in the provided tooling. If you run into
problems, please open an issue with detailed reproduction steps, environment
information, and logs. Clear reports make it much easier to reproduce and fix
problems for everyone.
