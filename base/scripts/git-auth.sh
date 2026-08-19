#!/usr/bin/env bash

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

NETRC_PATH="${HOME:-/root}/.netrc"

git_auth_setup() {
  if [[ -n "${GIT_TOKEN}" && -z "${GIT_HOST}" ]]; then
    echo "ERROR: GIT_TOKEN is set but GIT_HOST is empty." >&2
    return 2
  fi

  if [[ -z "${GITHUB_TOKEN}" && -z "${GITLAB_TOKEN}" && -z "${GIT_TOKEN}" ]]; then
    echo "INFO: No Git tokens provided - assuming public repositories only." >&2
    return 0
  fi

  local old_umask
  old_umask="$(umask)"
  umask 077
  : > "${NETRC_PATH}"

  if [[ -n "${GITHUB_TOKEN}" ]]; then
    printf 'machine %s login %s password %s\n' \
      "${GITHUB_HOST}" "${GITHUB_USER}" "${GITHUB_TOKEN}" >> "${NETRC_PATH}"
  fi

  if [[ -n "${GITLAB_TOKEN}" ]]; then
    printf 'machine %s login %s password %s\n' \
      "${GITLAB_HOST}" "${GITLAB_USER}" "${GITLAB_TOKEN}" >> "${NETRC_PATH}"
  fi

  if [[ -n "${GIT_TOKEN}" ]]; then
    printf 'machine %s login %s password %s\n' \
      "${GIT_HOST}" "${GIT_USER}" "${GIT_TOKEN}" >> "${NETRC_PATH}"
  fi

  chmod 600 "${NETRC_PATH}"
  umask "${old_umask}"
  unset GITHUB_TOKEN GITLAB_TOKEN GIT_TOKEN || true
  echo "INFO: Temporary .netrc created for Git authentication." >&2
}

git_auth_cleanup() {
  [[ -f "${NETRC_PATH}" ]] || return 0

  if command -v shred >/dev/null 2>&1; then
    shred -u "${NETRC_PATH}" || rm -f "${NETRC_PATH}"
  else
    rm -f "${NETRC_PATH}"
  fi
}
