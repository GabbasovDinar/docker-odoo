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
# --- Command dispatcher
if [[ $# -eq 0 ]]; then
  set -- odoo
fi

case "$1" in
  odoo)
    shift || true
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  --)
    shift || true
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  -*)
    exec odoo -c "${ODOO_RC}" "$@"
    ;;
  *)
    # arbitrary command (e.g., bash)
    exec "$@"
    ;;
esac
