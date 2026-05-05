#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Usage: %s <backup-directory>\n' "$0" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ENV_FILE="${ENV_FILE:-.env}"
COMPOSE_FILES="${COMPOSE_FILES:--f docker-compose.yml}"
COMPOSE_PROFILES="${COMPOSE_PROFILES:-}"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-docker-odoo}"
REQUESTED_COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}"

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  source "${ENV_FILE}"
  set +a
fi

COMPOSE_PROJECT_NAME="${REQUESTED_COMPOSE_PROJECT_NAME}"

read -r -a COMPOSE_FILE_ARGS <<< "${COMPOSE_FILES}"
read -r -a COMPOSE_PROFILE_ARGS <<< "${COMPOSE_PROFILES}"

compose() {
  local env_file="${ENV_FILE}"
  local project_name="${COMPOSE_PROJECT_NAME}"
  COMPOSE_PROJECT_NAME="${project_name}" ENV_FILE="${env_file}" \
    docker compose --env-file "${env_file}" "${COMPOSE_PROFILE_ARGS[@]}" "${COMPOSE_FILE_ARGS[@]}" "$@"
}

: "${DB_NAME:?DB_NAME is required}"
: "${DB_USER:?DB_USER is required}"

DATA_DIR="${DATA_DIR:-/var/lib/odoo}"
BACKUP_DIR="$1"
DB_DUMP="${BACKUP_DIR}/db.dump"
FILESTORE_ARCHIVE="${BACKUP_DIR}/filestore.tar.gz"

[[ -f "${DB_DUMP}" ]] || { printf 'Missing dump: %s\n' "${DB_DUMP}" >&2; exit 1; }
[[ -f "${FILESTORE_ARCHIVE}" ]] || { printf 'Missing filestore archive: %s\n' "${FILESTORE_ARCHIVE}" >&2; exit 1; }

compose stop odoo

cat "${DB_DUMP}" | compose exec -T db \
  pg_restore --clean --if-exists --create --no-owner --no-privileges \
  -U "${DB_USER}" -d postgres

# Container sees RESTORE_* from -e; host must not expand this script body.
# shellcheck disable=SC2016
cat "${FILESTORE_ARCHIVE}" | compose run --rm --no-deps -T \
  -e RESTORE_DATA_DIR="${DATA_DIR}" \
  -e RESTORE_DB_NAME="${DB_NAME}" \
  odoo bash -lc '
    set -euo pipefail
    rm -rf "${RESTORE_DATA_DIR}/filestore/${RESTORE_DB_NAME}"
    mkdir -p "${RESTORE_DATA_DIR}"
    tar -C "${RESTORE_DATA_DIR}" -xzf -
  '

compose start odoo

printf 'Restore completed from: %s\n' "${BACKUP_DIR}"
