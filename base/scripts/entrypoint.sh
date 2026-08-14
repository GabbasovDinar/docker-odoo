#!/usr/bin/env bash
set -euo pipefail


ODOO_RC="${ODOO_RC:-/etc/odoo.conf}"
TEMPLATE_CONF="${TEMPLATE_CONF:-${ODOO_RC_TEMPLATE:-/usr/local/share/odoo/tmpl/odoo.conf.tpl}}"

# ensure config dir exists
mkdir -p "$(dirname "${ODOO_RC}")"

# --- DB credentials (compose-friendly defaults)
: "${DB_HOST:=${DB_PORT_5432_TCP_ADDR:-db}}"
: "${DB_PORT:=${DB_PORT_5432_TCP_PORT:-5432}}"
: "${DB_USER:=${DB_ENV_POSTGRES_USER:-${POSTGRES_USER:-odoo}}}"
: "${DB_PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:-${POSTGRES_PASSWORD:-odoo}}}"

# Support *_FILE convention for passwords/secrets
if [[ -n "${DB_PASSWORD_FILE:-}" && -r "${DB_PASSWORD_FILE}" ]]; then
  DB_PASSWORD="$(<"${DB_PASSWORD_FILE}")"
fi
if [[ -z "${DB_PASSWORD:-}" && -n "${PASSWORD_FILE:-}" && -r "${PASSWORD_FILE}" ]]; then
  DB_PASSWORD="$(<"${PASSWORD_FILE}")"
fi

# --- Choose single env file for rendering
ENV_SRC=""
if [[ -n "${ODOO_ENV_FILE:-}" && -r "${ODOO_ENV_FILE}" ]]; then
  ENV_SRC="${ODOO_ENV_FILE}"
elif [[ -n "${ENV_FILE:-}" && -r "${ENV_FILE}" ]]; then
  ENV_SRC="${ENV_FILE}"
fi

load_runtime_env() {
  [[ -n "${ENV_SRC}" ]] || return 0

  # Reuse the project dotenv parser and shell-quote values before eval.
  # Only a fixed allow-list is exported; arbitrary .env keys are not sourced.
  eval "$(python - "${ENV_SRC}" <<'PY'
import importlib.util
import shlex
import sys

spec = importlib.util.spec_from_file_location("odoorc", "/usr/local/bin/odoorc.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
env = module.parse_env(sys.argv[1], treat_empty_unset=True)

keys = (
    "ODOO_VERSION",
    "OPENUPGRADE",
    "OPENUPGRADE_SOURCE_DATABASE_NAME",
    "OPENUPGRADE_TARGET_DATABASE_NAME",
    "OPENUPGRADE_DATABASE_NAME",
    "OPENUPGRADE_TARGET_VERSION",
    "OPENUPGRADE_FORCE",
    "OPENUPGRADE_RECREATE_DATABASE",
    "OPENUPGRADE_COPY_FILESTORE",
    "OPENUPGRADE_USE_DEMO",
    "OPENUPGRADE_RENAMED_MODULES",
    "OPENUPGRADE_MERGED_MODULES",
)
for key in keys:
    if key in env:
        print(f"export {key}={shlex.quote(env[key])}")
PY
)"
}

is_true() {
  case "${1:-}" in
    1|true|True|TRUE|yes|Yes|YES|on|On|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

load_runtime_env

if is_true "${OPENUPGRADE:-False}"; then
  OPENUPGRADE_TARGET_DATABASE_NAME="${OPENUPGRADE_TARGET_DATABASE_NAME:-${OPENUPGRADE_DATABASE_NAME:-}}"

  if [[ -z "${OPENUPGRADE_SOURCE_DATABASE_NAME:-}" ]]; then
    echo "ERROR: OPENUPGRADE=True requires OPENUPGRADE_SOURCE_DATABASE_NAME" >&2
    exit 2
  fi
  if [[ -z "${OPENUPGRADE_TARGET_DATABASE_NAME:-}" ]]; then
    echo "ERROR: OPENUPGRADE=True requires OPENUPGRADE_TARGET_DATABASE_NAME" >&2
    exit 2
  fi
  if [[ "${OPENUPGRADE_SOURCE_DATABASE_NAME}" == "${OPENUPGRADE_TARGET_DATABASE_NAME}" ]]; then
    echo "ERROR: source and target databases must be different" >&2
    exit 2
  fi

  export OPENUPGRADE_SOURCE_DATABASE_NAME
  export OPENUPGRADE_TARGET_DATABASE_NAME
  export DB_NAME="${OPENUPGRADE_TARGET_DATABASE_NAME}"
  export DATABASE_NAME="${OPENUPGRADE_TARGET_DATABASE_NAME}"
  export DBFILTER="$(python - "${OPENUPGRADE_TARGET_DATABASE_NAME}" <<'PY'
import re
import sys
print(f"^{re.escape(sys.argv[1])}$")
PY
)"
fi

# --- Render odoo.conf (drop-unresolved)
render_args=(--template "${TEMPLATE_CONF}" --out "${ODOO_RC}" --max-passes 5 --drop-unresolved)
if [[ -n "${ENV_SRC}" ]]; then
  render_args+=(--env "${ENV_SRC}")
fi
python /usr/local/bin/odoorc.py "${render_args[@]}"

# --- Wait for Postgres if helper available
if command -v wait-for-psql.py >/dev/null 2>&1; then
  WF_ARGS=(--db_host "${DB_HOST}" --db_port "${DB_PORT}" --db_user "${DB_USER}" --db_password "${DB_PASSWORD}" --timeout=30)
  wait-for-psql.py "${WF_ARGS[@]}"
fi

config_value() {
  local key="$1"

  awk -F= -v key="${key}" '
    $1 ~ "^[[:space:]]*" key "[[:space:]]*$" {
      value = $0
      sub(/^[^=]*=/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "${ODOO_RC}"
}

psql_odoo() {
  local db_name="$1"
  shift

  PGPASSWORD="${DB_PASSWORD}" psql \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    -d "${db_name}" \
    -v ON_ERROR_STOP=1 \
    -q \
    "$@"
}

sync_odoo_config_parameter() {
  local db_name="$1"
  local key="$2"
  local value="$3"

  [[ -n "${value}" ]] || return 0

  psql_odoo "${db_name}" \
    -v param_key="${key}" \
    -v param_value="${value}" <<'SQL'
INSERT INTO ir_config_parameter (key, value, create_uid, write_uid, create_date, write_date)
VALUES (:'param_key', :'param_value', 1, 1, now(), now())
ON CONFLICT (key)
DO UPDATE SET value = EXCLUDED.value, write_uid = 1, write_date = now();
SQL
}

start_odoo_url_parameter_sync() {
  local report_url="${ODOO_REPORT_URL:-${REPORT_URL:-}}"
  local base_url="${ODOO_BASE_URL:-}"
  local base_url_freeze="${ODOO_BASE_URL_FREEZE:-}"
  local db_name="${DB_NAME:-}"

  [[ -n "${report_url}${base_url}" ]] || return 0

  if ! command -v psql >/dev/null 2>&1; then
    echo "Skipping Odoo URL parameter sync: psql is not installed" >&2
    return 0
  fi

  if [[ -z "${db_name}" ]]; then
    db_name="$(config_value db_name || true)"
  fi
  if [[ -z "${db_name}" ]]; then
    echo "Skipping Odoo URL parameter sync: db_name is not configured" >&2
    return 0
  fi

  if [[ -n "${base_url}" && -z "${base_url_freeze}" ]]; then
    base_url_freeze="True"
  fi

  (
    deadline=$((SECONDS + 120))
    while ((SECONDS < deadline)); do
      if [[ "$(psql_odoo "${db_name}" -Atqc "SELECT to_regclass('public.ir_config_parameter') IS NOT NULL" 2>/dev/null || true)" == "t" ]]; then
        sync_odoo_config_parameter "${db_name}" "report.url" "${report_url}"
        sync_odoo_config_parameter "${db_name}" "web.base.url" "${base_url}"
        sync_odoo_config_parameter "${db_name}" "web.base.url.freeze" "${base_url_freeze}"
        echo "Synced Odoo URL parameters in database ${db_name}"
        return 0
      fi
      sleep 2
    done

    echo "Skipping Odoo URL parameter sync: ir_config_parameter was not ready within 120s" >&2
  ) &
}

cleanup_filesystem_sessions_for_redis() {
  case "${ODOO_SESSION_REDIS:-0}" in
    1|true|True|TRUE|yes|Yes|YES)
      ;;
    *)
      return 0
      ;;
  esac

  local session_dir="${ODOO_SESSION_DIR:-${DATA_DIR:-/var/lib/odoo}/sessions}"
  [[ -d "${session_dir}" ]] || return 0

  find "${session_dir}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  echo "Removed old filesystem sessions from ${session_dir}; Redis session storage is enabled"
}

database_exists() {
  local db_name="$1"
  local result

  result="$(psql_odoo postgres -At -v db_name="${db_name}" <<'SQL'
SELECT 1 FROM pg_database WHERE datname = :'db_name';
SQL
)"
  [[ "${result}" == "1" ]]
}

database_odoo_version() {
  local db_name="$1"

  psql_odoo "${db_name}" -Atqc \
    "SELECT COALESCE(latest_version, '') FROM ir_module_module WHERE name = 'base' LIMIT 1" \
    2>/dev/null || true
}

openupgrade_marker_matches() {
  local db_name="$1"
  local source_db="$2"
  local hop_version="$3"
  local table_exists
  local matches

  table_exists="$(psql_odoo "${db_name}" -Atqc "SELECT to_regclass('public.ir_config_parameter') IS NOT NULL" 2>/dev/null || true)"
  [[ "${table_exists}" == "t" ]] || return 1

  matches="$(psql_odoo "${db_name}" -At \
    -v source_db="${source_db}" \
    -v hop_version="${hop_version}" <<'SQL'
SELECT CASE WHEN
    EXISTS (
        SELECT 1 FROM ir_config_parameter
        WHERE key = 'docker_odoo.openupgrade.source_database'
          AND value = :'source_db'
    )
    AND EXISTS (
        SELECT 1 FROM ir_config_parameter
        WHERE key = 'docker_odoo.openupgrade.hop_version'
          AND value = :'hop_version'
    )
    AND EXISTS (
        SELECT 1 FROM ir_config_parameter
        WHERE key = 'docker_odoo.openupgrade.status'
          AND value = 'completed'
    )
THEN 1 ELSE 0 END;
SQL
)"

  [[ "${matches}" == "1" ]]
}

mark_openupgrade_success() {
  local db_name="$1"
  local source_db="$2"
  local hop_version="$3"

  sync_odoo_config_parameter "${db_name}" "docker_odoo.openupgrade.source_database" "${source_db}"
  sync_odoo_config_parameter "${db_name}" "docker_odoo.openupgrade.hop_version" "${hop_version}"
  sync_odoo_config_parameter "${db_name}" "docker_odoo.openupgrade.status" "completed"
  sync_odoo_config_parameter "${db_name}" "docker_odoo.openupgrade.completed_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}

copy_openupgrade_filestore() {
  local source_db="$1"
  local target_db="$2"
  local data_dir="${DATA_DIR:-/var/lib/odoo}"
  local source_dir="${data_dir}/filestore/${source_db}"
  local target_dir="${data_dir}/filestore/${target_db}"

  is_true "${OPENUPGRADE_COPY_FILESTORE:-True}" || return 0

  if [[ ! -d "${source_dir}" ]]; then
    echo "OpenUpgrade: source filestore not found at ${source_dir}; copy it separately if the database uses attachments" >&2
    return 0
  fi

  mkdir -p "${target_dir}"
  rsync -a --delete "${source_dir}/" "${target_dir}/"
  echo "OpenUpgrade: copied filestore ${source_db} -> ${target_db}"
}

clone_openupgrade_database() {
  local source_db="$1"
  local target_db="$2"
  local command_name

  for command_name in pg_dump pg_restore createdb dropdb; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
      echo "ERROR: ${command_name} is required for OpenUpgrade database cloning" >&2
      return 1
    fi
  done

  if database_exists "${target_db}"; then
    echo "OpenUpgrade: dropping target database ${target_db} before recreation"
    PGPASSWORD="${DB_PASSWORD}" dropdb \
      -h "${DB_HOST}" \
      -p "${DB_PORT}" \
      -U "${DB_USER}" \
      --maintenance-db=postgres \
      --if-exists \
      --force \
      "${target_db}"
  fi

  echo "OpenUpgrade: creating empty target database ${target_db}"
  PGPASSWORD="${DB_PASSWORD}" createdb \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    --maintenance-db=postgres \
    --owner="${DB_USER}" \
    --template=template0 \
    "${target_db}"

  echo "OpenUpgrade: cloning PostgreSQL database ${source_db} -> ${target_db}"
  if ! PGPASSWORD="${DB_PASSWORD}" pg_dump \
      -h "${DB_HOST}" \
      -p "${DB_PORT}" \
      -U "${DB_USER}" \
      --format=custom \
      --no-owner \
      --no-privileges \
      "${source_db}" \
      | PGPASSWORD="${DB_PASSWORD}" pg_restore \
          -h "${DB_HOST}" \
          -p "${DB_PORT}" \
          -U "${DB_USER}" \
          -d "${target_db}" \
          --no-owner \
          --no-privileges \
          --exit-on-error; then
    echo "ERROR: failed to clone ${source_db} into ${target_db}; target database was left in place for inspection" >&2
    return 1
  fi

  copy_openupgrade_filestore "${source_db}" "${target_db}"
}

run_openupgrade_if_enabled() {
  is_true "${OPENUPGRADE:-False}" || return 0

  local source_db="${OPENUPGRADE_SOURCE_DATABASE_NAME}"
  local target_db="${OPENUPGRADE_TARGET_DATABASE_NAME}"
  local hop_version="${ODOO_VERSION:-}"
  local final_target_version="${OPENUPGRADE_TARGET_VERSION:-${hop_version}}"
  local current_version

  if [[ -z "${hop_version}" ]]; then
    echo "ERROR: ODOO_VERSION must be set when OPENUPGRADE=True" >&2
    exit 2
  fi

  if [[ ! -d /opt/extra-addons/openupgrade_framework || ! -d /opt/extra-addons/openupgrade_scripts ]]; then
    echo "ERROR: OpenUpgrade addons are missing from /opt/extra-addons" >&2
    exit 2
  fi

  if ! database_exists "${source_db}"; then
    echo "ERROR: OpenUpgrade source database ${source_db} does not exist" >&2
    exit 2
  fi

  if database_exists "${target_db}"; then
    if openupgrade_marker_matches "${target_db}" "${source_db}" "${hop_version}" && ! is_true "${OPENUPGRADE_FORCE:-False}"; then
      current_version="$(database_odoo_version "${target_db}")"
      echo "OpenUpgrade: ${target_db} already completed ${source_db} -> ${hop_version} (${current_version:-unknown}); migration skipped"
      return 0
    fi

    if is_true "${OPENUPGRADE_RECREATE_DATABASE:-False}"; then
      clone_openupgrade_database "${source_db}" "${target_db}"
    elif openupgrade_marker_matches "${target_db}" "${source_db}" "${hop_version}" && is_true "${OPENUPGRADE_FORCE:-False}"; then
      echo "OpenUpgrade: force enabled; re-running migration on existing completed target ${target_db}" >&2
    else
      echo "ERROR: target database ${target_db} already exists without a matching successful migration marker" >&2
      echo "Set OPENUPGRADE_RECREATE_DATABASE=True to recreate it from ${source_db}, or choose another target database name" >&2
      exit 2
    fi
  else
    clone_openupgrade_database "${source_db}" "${target_db}"
  fi

  current_version="$(database_odoo_version "${target_db}")"
  export OPENUPGRADE_TARGET_VERSION="${final_target_version}"

  echo "OpenUpgrade: migrating copied database ${target_db} from ${current_version:-unknown} to ${hop_version}; final target=${final_target_version}"
  odoo \
    -c "${ODOO_RC}" \
    -d "${target_db}" \
    -u all \
    --stop-after-init \
    --no-http \
    --workers=0 \
    --max-cron-threads=0 \
    --load=base,web,openupgrade_framework

  current_version="$(database_odoo_version "${target_db}")"
  if [[ "${current_version}" != "${hop_version}"* ]]; then
    echo "ERROR: OpenUpgrade finished but base reports version '${current_version}', expected '${hop_version}*'" >&2
    exit 1
  fi

  mark_openupgrade_success "${target_db}" "${source_db}" "${hop_version}"
  echo "OpenUpgrade: migration ${source_db} -> ${target_db} completed successfully"
}

# --- Command dispatcher
if [[ $# -eq 0 ]]; then
  set -- odoo
fi

case "$1" in
  openupgrade)
    shift || true
    if ! is_true "${OPENUPGRADE:-False}"; then
      echo "ERROR: make migrate/openupgrade requires OPENUPGRADE=True" >&2
      exit 2
    fi
    cleanup_filesystem_sessions_for_redis
    run_openupgrade_if_enabled
    ;;
  odoo)
    shift || true
    cleanup_filesystem_sessions_for_redis
    run_openupgrade_if_enabled
    start_odoo_url_parameter_sync
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  --)
    shift || true
    cleanup_filesystem_sessions_for_redis
    run_openupgrade_if_enabled
    start_odoo_url_parameter_sync
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  -*)
    cleanup_filesystem_sessions_for_redis
    start_odoo_url_parameter_sync
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  *)
    # arbitrary command (e.g., bash)
    exec "$@"
    ;;
esac
