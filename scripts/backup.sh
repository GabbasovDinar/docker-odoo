#!/usr/bin/env bash
set -euo pipefail

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
BACKUP_ROOT="${BACKUP_ROOT:-${ROOT_DIR}/backups}"
STAMP="${1:-$(date +%F_%H-%M-%S)}"
TARGET_DIR="${BACKUP_ROOT}/${STAMP}"

mkdir -p "${TARGET_DIR}"

compose exec -T db \
  pg_dump -Fc --clean --if-exists --no-owner --no-privileges \
  -U "${DB_USER}" "${DB_NAME}" > "${TARGET_DIR}/db.dump"

# Inner bash -lc must receive literal $1/$2 for positional args.
# shellcheck disable=SC2016
compose exec -T odoo \
  bash -lc 'cd "$1"; if [[ -d "filestore/$2" ]]; then tar -czf - "filestore/$2"; else tar -czf - --files-from /dev/null; fi' \
  _ "${DATA_DIR}" "${DB_NAME}" > "${TARGET_DIR}/filestore.tar.gz"

cat > "${TARGET_DIR}/manifest.txt" <<EOF
created_at=${STAMP}
compose_project_name=${COMPOSE_PROJECT_NAME}
env_file=${ENV_FILE}
db_name=${DB_NAME}
data_dir=${DATA_DIR}
EOF

printf 'Backup created: %s\n' "${TARGET_DIR}"
