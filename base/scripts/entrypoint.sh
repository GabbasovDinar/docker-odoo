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

# --- Command dispatcher
if [[ $# -eq 0 ]]; then
  set -- odoo
fi

case "$1" in
  odoo)
    shift || true
    start_odoo_url_parameter_sync
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  --)
    shift || true
    start_odoo_url_parameter_sync
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  -*)
    start_odoo_url_parameter_sync
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  *)
    # arbitrary command (e.g., bash)
    exec "$@"
    ;;
esac
