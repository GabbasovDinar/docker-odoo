#!/usr/bin/env bash
set -uo pipefail

# OCA-style local addon test runner:
# 1. pre-install dependencies without tests;
# 2. install selected local addons with Odoo tests enabled.

ODOO_RC="${ODOO_RC:-/etc/odoo.conf}"
LOCAL_ADDONS_DIR="${LOCAL_ADDONS_DIR:-/opt/local-addons}"
DATA_DIR="${DATA_DIR:-/var/lib/odoo}"
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-5432}"
DB_USER="${DB_USER:-odoo}"
DB_PASSWORD="${DB_PASSWORD:-odoo}"

TEST_DB="${ODOO_TEST_DB:-}"
TEST_MODULES="${ODOO_TEST_MODULES:-}"
TEST_TAGS="${ODOO_TEST_TAGS:-}"
TEST_KEEP_DB="${ODOO_TEST_KEEP_DB:-0}"
TEST_DROP_FAILED_DB="${ODOO_TEST_DROP_FAILED_DB:-0}"

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

psql_admin() {
  PGPASSWORD="${DB_PASSWORD}" psql \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    -d postgres \
    -v ON_ERROR_STOP=1 \
    -q \
    "$@"
}

database_exists() {
  local db_name="$1"
  local result

  result="$(psql_admin -At -v db_name="${db_name}" <<'SQL'
SELECT 1 FROM pg_database WHERE datname = :'db_name';
SQL
)"
  [[ "${result}" == "1" ]]
}

database_is_initialized() {
  local db_name="$1"
  local result

  result="$(PGPASSWORD="${DB_PASSWORD}" psql \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    -d "${db_name}" \
    -Atqc "SELECT to_regclass('public.ir_module_module') IS NOT NULL" 2>/dev/null || true)"
  [[ "${result}" == "t" ]]
}

create_database() {
  local db_name="$1"

  PGPASSWORD="${DB_PASSWORD}" createdb \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    --maintenance-db=postgres \
    --owner="${DB_USER}" \
    --template=template0 \
    "${db_name}"
}

drop_database() {
  local db_name="$1"

  PGPASSWORD="${DB_PASSWORD}" dropdb \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    --maintenance-db=postgres \
    --if-exists \
    --force \
    "${db_name}"

  rm -rf -- "${DATA_DIR}/filestore/${db_name}" "${DATA_DIR}/sessions/${db_name}" 2>/dev/null || true
}

make_ephemeral_database_name() {
  local candidate

  while true; do
    candidate="odoo_test_$(date -u +%Y%m%d_%H%M%S)_${RANDOM}"
    if ! database_exists "${candidate}"; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done
}

list_local_addons() {
  manifestoo --select-addons-dir "${LOCAL_ADDONS_DIR}" list --separator=,
}

validate_requested_modules() {
  local all_modules="$1"
  local requested="$2"
  local module
  local normalized=""

  IFS=',' read -ra requested_modules <<< "${requested}"
  for module in "${requested_modules[@]}"; do
    module="${module//[[:space:]]/}"
    [[ -n "${module}" ]] || continue
    if [[ "${module}" == *[!A-Za-z0-9_]* ]]; then
      echo "ERROR: invalid addon name in TEST_MODULES: ${module}" >&2
      return 2
    fi
    if [[ ",${all_modules}," != *",${module},"* ]]; then
      echo "ERROR: TEST_MODULES contains '${module}', which is not an installable addon under ${LOCAL_ADDONS_DIR}" >&2
      return 2
    fi
    normalized+="${normalized:+,}${module}"
  done

  printf '%s\n' "${normalized}"
}

list_dependencies() {
  local modules="$1"

  manifestoo --select-include "${modules}" list-depends --separator=,
}

module_test_tags() {
  local modules="$1"
  local module
  local tags=""

  IFS=',' read -ra module_names <<< "${modules}"
  for module in "${module_names[@]}"; do
    [[ -n "${module}" ]] || continue
    tags+="${tags:+,}/${module}"
  done
  printf '%s\n' "${tags}"
}

installed_local_addons() {
  local db_name="$1"
  local modules="$2"
  local installed
  local module
  local selected=""

  installed="$(PGPASSWORD="${DB_PASSWORD}" psql \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    -d "${db_name}" \
    -Atqc "SELECT name FROM ir_module_module WHERE state IN ('installed', 'to upgrade') ORDER BY name")"

  IFS=',' read -ra module_names <<< "${modules}"
  for module in "${module_names[@]}"; do
    [[ -n "${module}" ]] || continue
    if grep -Fxq -- "${module}" <<< "${installed}"; then
      selected+="${selected:+,}${module}"
    fi
  done

  printf '%s\n' "${selected}"
}

run_odoo() {
  local db_name="$1"
  shift

  odoo \
    -c "${ODOO_RC}" \
    "$@" \
    -d "${db_name}" \
    --workers=0 \
    --max-cron-threads=0 \
    --http-interface=127.0.0.1 \
    --stop-after-init
}

initialize_test_database() {
  local db_name="$1"
  local modules="$2"
  local dependencies
  local bootstrap_modules

  dependencies="$(list_dependencies "${modules}")" || return $?
  bootstrap_modules="${dependencies}"
  if [[ ",${bootstrap_modules}," != *",base,"* ]]; then
    bootstrap_modules="base${bootstrap_modules:+,${bootstrap_modules}}"
  fi

  echo "Test mode: installing dependencies without tests: ${bootstrap_modules}"
  run_odoo "${db_name}" \
    --without-demo=all \
    -i "${bootstrap_modules}"
}

run_fresh_tests() {
  local db_name="$1"
  local modules="$2"
  shift 2
  local args=("$@")

  echo "Test mode: installing and testing local addons: ${modules}"
  if [[ -n "${TEST_TAGS}" ]]; then
    echo "Test mode: Odoo test tags: ${TEST_TAGS}"
    run_odoo "${db_name}" \
      "${args[@]}" \
      --without-demo=all \
      -i "${modules}" \
      --test-enable \
      --test-tags "${TEST_TAGS}"
  else
    run_odoo "${db_name}" \
      "${args[@]}" \
      --without-demo=all \
      -i "${modules}" \
      --test-enable
  fi
}

run_existing_tests() {
  local db_name="$1"
  local modules="$2"
  shift 2
  local args=("$@")
  local installed_modules
  local tags

  installed_modules="$(installed_local_addons "${db_name}" "${modules}")" || return $?
  if [[ -z "${installed_modules}" ]]; then
    echo "ERROR: none of the selected local addons are installed in database '${db_name}'" >&2
    return 2
  fi

  if [[ -n "${TEST_MODULES}" && "${installed_modules}" != "${modules}" ]]; then
    echo "ERROR: not every addon from TEST_MODULES is installed in database '${db_name}'" >&2
    echo "Selected:  ${modules}" >&2
    echo "Installed: ${installed_modules}" >&2
    return 2
  fi

  if [[ "${installed_modules}" != "${modules}" ]]; then
    echo "Test mode: only installed local addons will be tested: ${installed_modules}"
  fi

  tags="${TEST_TAGS:-$(module_test_tags "${installed_modules}")}"
  echo "Test mode: running tests on existing database '${db_name}'"
  echo "Test mode: Odoo test tags: ${tags}"
  echo "WARNING: existing-database tests are not isolated; do not use a production database." >&2

  run_odoo "${db_name}" \
    "${args[@]}" \
    --test-enable \
    --test-tags "${tags}"
}

main() {
  local all_modules
  local modules
  local db_name
  local generated_db=0
  local initialized=0
  local rc=0

  if [[ ! -d "${LOCAL_ADDONS_DIR}" ]]; then
    echo "ERROR: local addons directory does not exist: ${LOCAL_ADDONS_DIR}" >&2
    return 2
  fi

  all_modules="$(list_local_addons)" || return $?
  if [[ -z "${all_modules}" ]]; then
    echo "Test mode: no installable addons found under ${LOCAL_ADDONS_DIR}; nothing to test."
    return 0
  fi

  if [[ -n "${TEST_MODULES}" ]]; then
    modules="$(validate_requested_modules "${all_modules}" "${TEST_MODULES}")" || return $?
  else
    modules="${all_modules}"
  fi

  if [[ -z "${modules}" ]]; then
    echo "Test mode: no addons selected; nothing to test."
    return 0
  fi

  if [[ -n "${TEST_DB}" ]]; then
    db_name="${TEST_DB}"
    case "${db_name}" in
      postgres|template0|template1)
        echo "ERROR: refusing to run tests on PostgreSQL system database '${db_name}'" >&2
        return 2
        ;;
    esac
    if ! database_exists "${db_name}"; then
      echo "ERROR: TEST_DB '${db_name}' does not exist" >&2
      return 2
    fi
    if database_is_initialized "${db_name}"; then
      initialized=1
    fi
  else
    db_name="$(make_ephemeral_database_name)" || return $?
    echo "Test mode: creating ephemeral database '${db_name}'"
    create_database "${db_name}" || return $?
    generated_db=1
  fi

  if [[ ${initialized} -eq 0 ]]; then
    initialize_test_database "${db_name}" "${modules}"
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
      run_fresh_tests "${db_name}" "${modules}" "$@"
      rc=$?
    fi
  else
    run_existing_tests "${db_name}" "${modules}" "$@"
    rc=$?
  fi

  if [[ ${generated_db} -eq 1 ]]; then
    if [[ ${rc} -eq 0 ]]; then
      if is_true "${TEST_KEEP_DB}"; then
        echo "Test mode: tests passed; keeping database '${db_name}' because TEST_KEEP_DB is enabled."
      else
        echo "Test mode: tests passed; dropping ephemeral database '${db_name}'."
        if ! drop_database "${db_name}"; then
          echo "ERROR: tests passed but cleanup of database '${db_name}' failed" >&2
          return 1
        fi
      fi
    else
      if is_true "${TEST_DROP_FAILED_DB}"; then
        echo "Test mode: tests failed; dropping database '${db_name}' because TEST_DROP_FAILED_DB is enabled." >&2
        drop_database "${db_name}" || true
      else
        echo "Test mode: tests failed; preserving database '${db_name}' for inspection." >&2
        echo "Re-run on the preserved database with: make test TEST_DB=${db_name}" >&2
        echo "Run plain 'make test' for a new clean database." >&2
      fi
    fi
  fi

  return "${rc}"
}

main "$@"
