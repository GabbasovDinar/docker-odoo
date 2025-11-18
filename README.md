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
├── caddy/
│   ├── Caddyfile               # Caddy reverse-proxy config
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

## Additional make targets

The Makefile also exposes a few utility commands that are handy when managing your stack:

* `make pull` — download the latest base images defined in docker-compose.yml.
* `make ps` — show the status of services and their port mappings.
* `make prune` — remove unused build cache layers from the Docker daemon.

Run `make help` to see a full list of available targets and their descriptions. These helpers wrap long docker compose commands so you do not have to remember them.

The stack exposes Odoo on port 8069 by default. Adjust the port mapping inside
`docker-compose.yml` if you need a different host port.

### Using Caddy as an HTTPS reverse proxy

This repository ships with a [Caddy](https://caddyserver.com/) service that can
terminate TLS certificates from Let's Encrypt and proxy traffic to Odoo.

1. Point your DNS records at the host running the stack (for example, add
   `A`/`AAAA` records for `example.com`).
2. Set the following variables in `.env`:
   * `CADDY_DOMAIN` to the public host name(s), e.g. `example.com` or
     `example.com www.example.com` for a redirect-less dual-host setup.
   * `CADDY_EMAIL` to the email address Caddy should use when requesting
     certificates.
   * `PROXY_MODE=True` so Odoo honours `X-Forwarded-*` headers from the proxy.
3. Start the stack as usual (`make up` or `docker compose up -d`). Caddy will
   listen on ports 80/443, obtain certificates automatically, and forward
   `/longpolling` and `/websocket` traffic to port 8072 while proxying regular
   HTTP requests to port 8069. Odoo 18's realtime bus uses WebSockets when
   available, and the default [`Caddyfile`](caddy/Caddyfile) keeps the upgrade
   requests on the dedicated longpolling worker.

The root-level [`Caddyfile`](caddy/Caddyfile) uses environment variables and a
reusable `(odoo_site)` snippet so you can add more hosts without duplicating
boilerplate. For example, hosting two databases behind
virtual hosts while forwarding the database name through an
[`dbfilter_from_header`](https://apps.odoo.com/apps/modules/18.0/dbfilter_from_header)-style
module can be achieved with a single Caddyfile:

```
example.com {
  import odoo_site
}

client1.example.com {
  import odoo_site

  # Optional: pin a database for dbfilter_from_header-style routing
  header { request set X-Odoo-Dbfilter client1_db }
}

client2.example.com {
  import odoo_site
  header { request set X-Odoo-Dbfilter client2_db }
}
```

#### Optional: protect the database manager with HTTP basic auth

By default the Odoo database manager (`/web/database/*`) is reachable behind Caddy as long as you know the master password. If you want an extra layer of protection, the bundled [`caddy/Caddyfile`](caddy/Caddyfile) contains a commented `basic_auth` block that can be enabled.

Uncomment the lines in the `(odoo_site)` snippet:

```caddyfile
# Site snippet
(odoo_site) {
  encode zstd gzip

  # Uncomment to enable basic auth to database manager
  @db_manager path /web/database/*

  handle @db_manager {
    basic_auth {
      <USER> <PASSHASH>
    }

    reverse_proxy odoo:8069 {
      import odoo_headers
    }
  }

  respond @db_manager 403

  @realtime {
    path /longpolling/* /websocket
  }

  handle @realtime {
    reverse_proxy odoo:8072 {
      import odoo_headers
    }
  }

  handle {
    reverse_proxy odoo:8069 {
      import odoo_headers
    }
  }
}
```

Replace `<USER>` with the username you want to use, and `<PASSHASH>` with a bcrypt hash of the password. Caddy does not accept plaintext passwords in the Caddyfile; you must hash them first.

You can generate a compatible hash with Caddy’s built-in command:

```
caddy hash-password --algorithm bcrypt --plaintext 'your-password'
```

or via Docker:

```
docker run --rm caddy:2.8.4-alpine \
  caddy hash-password --algorithm bcrypt --plaintext 'your-password'
```

Copy the resulting hash into the `basic_auth` block and reload the stack (`make restart` or `docker compose restart caddy`). After that, browsers will prompt for HTTP Basic Authentication before showing the Odoo database manager.

Keep in mind that HTTP basic auth is only considered secure when used over HTTPS, which Caddy enables by default in this setup.

### Localhost testing with Caddy

You can exercise the full Caddy + Odoo chain on a laptop without public DNS or
valid ACME certificates. The easiest path is to lean on the special
`.localhost` suffix, which Caddy automatically secures with an internal CA:

1. Add host entries on your machine (macOS/Linux) so the browser resolves to
   the Docker host:

   ```bash
   echo "127.0.0.1 odoo.localhost" | sudo tee -a /etc/hosts
   ```

2. Edit `.env` with local defaults:

   ```bash
   CADDY_DOMAIN=odoo.localhost
   CADDY_EMAIL=local@example.test   # arbitrary for local use
   PROXY_MODE=True                  # let Odoo trust Caddy's headers
   ```

3. Start the stack and open `https://odoo.localhost`:

   ```bash
   make up
   ```

   Caddy will issue a local certificate from its internal authority. Your
   browser may require trusting that root certificate; you can export it with:

   ```bash
   docker compose exec caddy cat /data/caddy/pki/authorities/local/root.crt > caddy-local-root.crt
   ```

   Import `caddy-local-root.crt` into your OS/browser trust store to clear TLS
   warnings. When finished, run `make down` to stop the containers.

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

## Private repositories & authentication

When your extra addons live in private Git repositories you need to
authenticate to fetch them. Populate the appropriate token variables in
`.env` so the `extra-addons.sh` helper can create a `.netrc` for Git:

* `GITHUB_TOKEN / GITLAB_TOKEN`— personal access tokens for GitHub or
GitLab repositories (default `GITHUB_HOST/GITLAB_HOST` values are used).
* `GIT_TOKEN` — generic token for other Git hosts; set together with
`GIT_HOST` (the hostname) and `GIT_USER` (the username used for token auth).

If your addons repositories are public you can leave these variables empty.
See the "Git credentials for private repositories" section in .env.example
for all available variables.

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

## Installing extra Python dependencies

During the addons build stage you can install additional Python packages required
by your custom modules. List these packages in `addons/requirements.txt`
(one per line, lines beginning with # are ignored) and they will be installed
into the image when you run make build-addons or make build.

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
