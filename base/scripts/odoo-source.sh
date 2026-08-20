#!/usr/bin/env bash
set -euo pipefail

: "${ODOO_REPO:=https://github.com/odoo/odoo.git}"
: "${ODOO_REF:=19.0}"
: "${ODOO_DIR:=/opt/odoo}"

# shellcheck source=base/scripts/git-auth.sh
source /usr/local/lib/odoo/git-auth.sh

trap git_auth_cleanup EXIT
git_auth_setup

mkdir -p "${ODOO_DIR}"

git init "${ODOO_DIR}"
git -C "${ODOO_DIR}" remote add origin "${ODOO_REPO}"
git -C "${ODOO_DIR}" fetch --depth=1 --no-tags origin "${ODOO_REF}"
git -C "${ODOO_DIR}" checkout --detach FETCH_HEAD

resolved_ref="$(git -C "${ODOO_DIR}" rev-parse HEAD)"
echo "INFO: Odoo source ready at ${resolved_ref} from ${ODOO_REPO}." >&2

rm -rf "${ODOO_DIR}/.git"
