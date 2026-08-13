# OpenUpgrade workflow

This repository can run OpenUpgrade before normal Odoo startup. The intended use is a disposable/test copy of a database, not the source production database.

## Version rule

OpenUpgrade migrates one major version at a time. Use the repository branch matching the target Odoo version:

- Odoo 16 -> 17: branch `17.0`, `OPENUPGRADE_TARGET_VERSION=17.0`
- Odoo 17 -> 18: branch `18.0`, `OPENUPGRADE_TARGET_VERSION=18.0`

Do not skip directly from 16 to 18.

## Database on an external PostgreSQL server

The migration database can live on the same external PostgreSQL server as the source database. Create a copy there and point the normal DB connection variables at that PostgreSQL server:

```env
DB_HOST=postgres.example.internal
DB_PORT=5432
DB_USER=odoo
DB_PASSWORD=...

OPENUPGRADE=True
OPENUPGRADE_DATABASE_NAME=odoo_migration_17
OPENUPGRADE_TARGET_VERSION=17.0
OPENUPGRADE_FORCE=False
```

`OPENUPGRADE_DATABASE_NAME` overrides `DB_NAME` inside the Odoo container while OpenUpgrade mode is enabled. This prevents the container from upgrading the normal `DB_NAME` by accident.

The bundled `db` service may still start, but Odoo connects to `DB_HOST`; for this migration/test setup the unused local PostgreSQL container is harmless.

## What happens on startup

With `OPENUPGRADE=True`, the entrypoint:

1. reads only the OpenUpgrade-related values from the mounted `.env`;
2. switches Odoo to `OPENUPGRADE_DATABASE_NAME`;
3. checks the installed `base` module version in PostgreSQL;
4. if the database is not already on the target major version, runs:

```text
odoo -d <database> -u all --stop-after-init --no-http --workers=0 --max-cron-threads=0 --load=base,web,openupgrade_framework
```

5. verifies that `base.latest_version` starts with the requested target version;
6. starts normal Odoo on the migrated database.

On later container restarts the migration is skipped when the database already reports the target version. Set `OPENUPGRADE_FORCE=True` only when intentionally developing/retrying migration scripts.

## OpenUpgrade sources

The target branch includes `OCA/OpenUpgrade` in `addons/addons.yml`. During the addons image build, `openupgrade_framework`, `openupgrade_scripts`, and their Python dependency `openupgradelib` become available in `/opt/extra-addons`.

`openupgrade_framework` automatically exposes the official OpenUpgrade migration scripts through Odoo's upgrade path when `openupgrade_scripts` is present.

## Custom migration scripts

For scripts that belong to one of your custom Odoo modules, prefer the normal module-local layout:

```text
local-addons/my_module/
  __manifest__.py
  upgrades/
    18.0.2.0/
      pre-10-migrate.py
      post-10-migrate.py
      end-10-migrate.py
```

The version directory must be greater than the version currently installed in the database and not greater than the target module version.

For upgrade scripts kept outside the module, use the existing `UPGRADE_PATH` option. `local-addons` is already bind-mounted, so no additional Docker volume is needed:

```env
UPGRADE_PATH=/opt/local-addons/upgrade
```

Example:

```text
local-addons/upgrade/
  my_module/
    18.0.2.0/
      pre-10-migrate.py
      post-10-migrate.py
```

Odoo accepts a comma-separated list in `UPGRADE_PATH` if several additional upgrade-script directories are needed.

## 16 -> 17 -> 18 test migration

### Step 1: create the 16 database copy

Create a database copy on the external PostgreSQL server, for example `odoo_migration_17`. Keep the source Odoo 16 database untouched.

### Step 2: migrate 16 -> 17

Checkout `17.0`, build it, and use:

```env
ODOO_VERSION=17.0
OPENUPGRADE=True
OPENUPGRADE_DATABASE_NAME=odoo_migration_17
OPENUPGRADE_TARGET_VERSION=17.0
```

Then:

```bash
make init
make up
make log-odoo
```

When the migration succeeds, the same container continues as a normal Odoo 17 instance on `odoo_migration_17`. Test the application and custom modules before continuing.

### Step 3: create the 17 -> 18 copy

For repeatable testing, make another PostgreSQL copy of the successfully migrated 17 database, for example `odoo_migration_18`.

### Step 4: migrate 17 -> 18

Checkout `18.0` and use:

```env
ODOO_VERSION=18.0
OPENUPGRADE=True
OPENUPGRADE_DATABASE_NAME=odoo_migration_18
OPENUPGRADE_TARGET_VERSION=18.0
```

Then rebuild and start:

```bash
make init
make up
make log-odoo
```

After success, the same container continues as normal Odoo 18 on `odoo_migration_18`.

## Failure handling

A failed OpenUpgrade run can leave the test database partially migrated. For a trustworthy full migration test, restore/recreate the database copy from the previous major version and run the complete `-u all` migration again after fixing the scripts.

For faster development of a specific migration script you can deliberately work against a disposable database copy and rerun only the affected module manually, but the final validation must be a clean full migration from a fresh copy.
