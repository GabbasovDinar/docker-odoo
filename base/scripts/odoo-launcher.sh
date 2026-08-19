#!/usr/bin/env bash
set -euo pipefail

ODOO_REAL="${ODOO_REAL:-/opt/odoo-venv/bin/odoo-real}"

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

if [[ "${MODE:-prod}" == "dev" && "${1:-}" == -* ]] && ! is_true "${OPENUPGRADE:-False}"; then
  exec python /usr/local/bin/odoo-debug.py \
    "$@" \
    --dev="${DEV_MODE:-all}" \
    --workers=0
fi

exec "${ODOO_REAL}" "$@"
