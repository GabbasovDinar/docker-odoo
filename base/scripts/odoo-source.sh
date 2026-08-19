#!/usr/bin/env bash
set -euo pipefail

: "${ODOO_REPO:=https://github.com/odoo/odoo.git}"
: "${ODOO_REF:=17.0}"
: "${ODOO_DIR:=/opt/odoo}"

: "${GITHUB_HOST:=github.com}"
: "${GITLAB_HOST:=gitlab.com}"
: "${GIT_HOST:=}"

: "${GITHUB_USER:=x-access-token}"
: "${GITLAB_USER:=oauth2}"
: "${GIT_USER:=oauth2}"

: "${GITHUB_TOKEN:=}"
: "${GITLAB_TOKEN:=}"
: "${GIT_TOKEN:=}"

export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true

HOME_DIR="${HOME:-/root}"
NETRC_PATH="${HOME_DIR}/.netrc"

if [[ -n "${GIT_TOKEN}" && -z "${GIT_HOST}" ]]; then
  echo "ERROR: GIT_TOKEN is set but GIT_HOST is empty." >&2
  exit 2
fi

create_netrc() {
  if [[ -z "${GITHUB_TOKEN}" && -z "${GITLAB_TOKEN}" && -z "${GIT_TOKEN}" ]]; then
    echo "INFO: No Git tokens provided - assuming a public Odoo repository." >&2
    return 0
  fi

  local old_umask
  old_umask="$(umask)"
  umask 077
  : > "${NETRC_PATH}"

  if [[ -n "${GITHUB_TOKEN}" ]]; then
    printf "machine %s login %s password %s\n" \
      "${GITHUB_HOST}" "${GITHUB_USER}" "${GITHUB_TOKEN}" >> "${NETRC_PATH}"
  fi

  if [[ -n "${GITLAB_TOKEN}" ]]; then
    printf "machine %s login %s password %s\n" \
      "${GITLAB_HOST}" "${GITLAB_USER}" "${GITLAB_TOKEN}" >> "${NETRC_PATH}"
  fi

  if [[ -n "${GIT_TOKEN}" ]]; then
    printf "machine %s login %s password %s\n" \
      "${GIT_HOST}" "${GIT_USER}" "${GIT_TOKEN}" >> "${NETRC_PATH}"
  fi

  chmod 600 "${NETRC_PATH}"
  umask "${old_umask}"
  echo "INFO: Temporary .netrc created for Odoo source authentication." >&2
}

cleanup_netrc() {
  if [[ -f "${NETRC_PATH}" ]]; then
    if command -v shred >/dev/null 2>&1; then
      shred -u "${NETRC_PATH}" || rm -f "${NETRC_PATH}"
    else
      rm -f "${NETRC_PATH}"
    fi
  fi
}

trap cleanup_netrc EXIT

create_netrc
unset GITHUB_TOKEN GITLAB_TOKEN GIT_TOKEN || true

mkdir -p "${ODOO_DIR}"

git init "${ODOO_DIR}"
git -C "${ODOO_DIR}" remote add origin "${ODOO_REPO}"
git -C "${ODOO_DIR}" fetch --depth=1 --no-tags origin "${ODOO_REF}"
git -C "${ODOO_DIR}" checkout --detach FETCH_HEAD

resolved_ref="$(git -C "${ODOO_DIR}" rev-parse HEAD)"
echo "INFO: Odoo source ready at ${resolved_ref} from ${ODOO_REPO}." >&2

rm -rf "${ODOO_DIR}/.git"
