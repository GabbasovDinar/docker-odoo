#!/usr/bin/env bash
set -euo pipefail

# -------------------- Defaults --------------------
: "${TMP_ADDONS_DIR:=/tmp/getaddons}"

: "${GITHUB_HOST:=github.com}"
: "${GITLAB_HOST:=gitlab.com}"
: "${GIT_HOST:=}" # generic git host

: "${GITHUB_USER:=x-access-token}"
: "${GITLAB_USER:=oauth2}"
: "${GIT_USER:=oauth2}" # generic git user

: "${GITHUB_TOKEN:=}"
: "${GITLAB_TOKEN:=}"
: "${GIT_TOKEN:=}" # generic git token

ADDONS_FILE=""

load_env_file() {
  local env_file="$1"

  if [[ ! -r "${env_file}" ]]; then
    if [[ -e "${env_file}" ]]; then
      echo "WARNING: --env-file provided but not readable: ${env_file}" >&2
    else
      echo "INFO: --env-file provided but not found: ${env_file} (continuing without it)" >&2
    fi
    return 0
  fi

  echo "INFO: Loading environment variables from ${env_file}" >&2
  while IFS='=' read -r key value; do
    case "${key}" in
      GITHUB_HOST|GITLAB_HOST|GIT_HOST|GITHUB_USER|GITLAB_USER|GIT_USER|GITHUB_TOKEN|GITLAB_TOKEN|GIT_TOKEN)
        printf -v "${key}" '%s' "${value}"
        export "${key?}"
        ;;
    esac
  done < <(python3 - "${env_file}" <<'PY'
import re
import sys

path = sys.argv[1]
key_re = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def store(key, value):
    if key_re.match(key):
        print(f"{key}={value}")


with open(path, encoding="utf-8") as fh:
    for raw in fh:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        if "=" not in line:
            continue

        key, value = line.split("=", 1)
        key = key.strip()
        value = value.rstrip("\r")

        if value.startswith('"') and value.endswith('"') and len(value) >= 2:
            try:
                value = bytes(value[1:-1], "utf-8").decode("unicode_escape")
            except Exception:
                value = value[1:-1]
        elif value.startswith("'") and value.endswith("'") and len(value) >= 2:
            value = value[1:-1]
        else:
            value = re.split(r"\s+#", value, 1)[0].strip()

        store(key, value)
PY
  )
}

# -------------------- Pre-scan only --env-file ----
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
  case "${ARGS[i]}" in
    --env-file=*)
      ENV_FILE="${ARGS[i]#*=}"
      ;;
    --env-file)
      if (( i+1 < ${#ARGS[@]} )); then ENV_FILE="${ARGS[i+1]}"; fi
      ;;
  esac
done

# -------------------- Load selected .env variables --------------------
if [[ -n "${ENV_FILE:-}" ]]; then
  load_env_file "${ENV_FILE}"
else
  echo "INFO: No --env-file provided; relying on environment variables." >&2
fi

# -------------------- Args --------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --addons-file)       ADDONS_FILE="${2:-}"; shift 2 ;;
    --addons-file=*)     ADDONS_FILE="${1#*=}"; shift ;;
    --addons-dir)        ADDONS_DIR="${2:-}"; shift 2 ;;
    --addons-dir=*)      ADDONS_DIR="${1#*=}"; shift ;;
    --env-file)          ENV_FILE="${2:-}"; shift 2 ;;
    --env-file=*)        ENV_FILE="${1#*=}"; shift ;;

    --github-user)       GITHUB_USER="${2:-}"; shift 2 ;;
    --github-user=*)     GITHUB_USER="${1#*=}"; shift ;;
    --github-token)      GITHUB_TOKEN="${2:-}"; shift 2 ;;
    --github-token=*)    GITHUB_TOKEN="${1#*=}"; shift ;;
    --github-host)       GITHUB_HOST="${2:-}"; shift 2 ;;
    --github-host=*)     GITHUB_HOST="${1#*=}"; shift ;;

    --gitlab-user)       GITLAB_USER="${2:-}"; shift 2 ;;
    --gitlab-user=*)     GITLAB_USER="${1#*=}"; shift ;;
    --gitlab-token)      GITLAB_TOKEN="${2:-}"; shift 2 ;;
    --gitlab-token=*)    GITLAB_TOKEN="${1#*=}"; shift ;;
    --gitlab-host)       GITLAB_HOST="${2:-}"; shift 2 ;;
    --gitlab-host=*)     GITLAB_HOST="${1#*=}"; shift ;;

    --git-user)          GIT_USER="${2:-}"; shift 2 ;;
    --git-user=*)        GIT_USER="${1#*=}"; shift ;;
    --git-token)         GIT_TOKEN="${2:-}"; shift 2 ;;
    --git-token=*)       GIT_TOKEN="${1#*=}"; shift ;;
    --git-host)          GIT_HOST="${2:-}"; shift 2 ;;
    --git-host=*)        GIT_HOST="${1#*=}"; shift ;;

    *)
      echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# -------------------- Git non-interactive --------------------
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/bin/true

HOME_DIR="${HOME:-/root}"
NETRC_PATH="${HOME_DIR}/.netrc"

if [[ -n "${GIT_TOKEN:-}" && -z "${GIT_HOST:-}" ]]; then
  echo "ERROR: --git-token provided but --git-host is empty." >&2
  exit 2
fi

create_netrc() {
  if [[ -z "${GITHUB_TOKEN:-}" && -z "${GITLAB_TOKEN:-}" && -z "${GIT_TOKEN:-}" ]]; then
    echo "INFO: No Git tokens provided — assuming public repositories only." >&2
    return 0
  fi

  local old_umask
  old_umask=$(umask)
  umask 077
  : > "${NETRC_PATH}"

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf "machine %s login %s password %s\n" \
      "${GITHUB_HOST}" "${GITHUB_USER}" "${GITHUB_TOKEN}" >>"${NETRC_PATH}"
  fi

  if [[ -n "${GITLAB_TOKEN:-}" ]]; then
    printf "machine %s login %s password %s\n" \
      "${GITLAB_HOST}" "${GITLAB_USER}" "${GITLAB_TOKEN}" >>"${NETRC_PATH}"
  fi

  if [[ -n "${GIT_TOKEN:-}" && -n "${GIT_HOST:-}" ]]; then
    printf "machine %s login %s password %s\n" \
      "${GIT_HOST}" "${GIT_USER}" "${GIT_TOKEN}" >>"${NETRC_PATH}"
  fi

  chmod 600 "${NETRC_PATH}"
  umask "${old_umask}"
  echo "INFO: .netrc created for Git authentication." >&2
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

# -------------------- Prepare --------------------
create_netrc
unset GITHUB_TOKEN GITLAB_TOKEN GIT_TOKEN || true

mkdir -p "$TMP_ADDONS_DIR" "$ADDONS_DIR"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "ci@example.com"
git config --global user.name  >/dev/null 2>&1 || git config --global user.name  "CI"

# -------------------- Resolve addons.yml --------------------
ADDONS_YML="$TMP_ADDONS_DIR/addons.yml"
if [[ -n "$ADDONS_FILE" ]]; then
  [[ -f "$ADDONS_FILE" ]] || { echo "addons file not found: $ADDONS_FILE" >&2; exit 2; }
  cp -f "$ADDONS_FILE" "$ADDONS_YML"
elif [[ ! -f "$ADDONS_YML" ]]; then
  echo "addons.yml not found at $ADDONS_YML" >&2
  exit 2
fi

# -------------------- Aggregate --------------------
(
  cd "$TMP_ADDONS_DIR"
  if [[ -n "${ENV_FILE:-}" && -r "${ENV_FILE}" ]]; then
    gitaggregate -c "$ADDONS_YML" --expand-env --env-file "${ENV_FILE}"
  else
    gitaggregate -c "$ADDONS_YML" --expand-env
  fi
)

# -------------------- Copy real addons --------------------
for repo in "${TMP_ADDONS_DIR}"/*; do
  [[ -d "${repo}" ]] || continue
  csv="$(manifestoo -d "${repo}" list --separator=,)"
  IFS=',' read -r -a mods <<< "${csv}"
  for mod in "${mods[@]}"; do
    [[ -n "${mod:-}" ]] || continue
    rsync -a --exclude='.git' "${repo}/${mod}/" "${ADDONS_DIR}/${mod}/"
  done
done

# -------------------- Install Debian deps --------------------
if [[ -n "$(ls -A "$ADDONS_DIR" 2>/dev/null || true)" ]]; then
  deps="$(manifestoo -d "$ADDONS_DIR" list-external-dependencies deb --transitive --ignore-missing || true)"
  if [[ -n "$deps" ]]; then
    apt-get update -qq
    read -r -a _debs <<< "$deps"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${_debs[@]}"
    rm -rf /var/lib/apt/lists/*
  fi
fi

# -------------------- Build unified Python requirements --------------------
combined_reqs="${ADDONS_DIR}/requirements.txt"
: > "${combined_reqs}"

for repo in "${TMP_ADDONS_DIR}"/*; do
  [[ -d "${repo}" ]] || continue

  if [[ -f "${repo}/requirements.txt" ]]; then
    awk '$0 !~ /^[[:space:]]*#/ && NF' "${repo}/requirements.txt" >> "${combined_reqs}"
  fi

  manifestoo -d "${repo}" list-external-dependencies python --transitive --ignore-missing --separator='|' \
    | tr '|' '\n' >> "${combined_reqs}" || true
done

# Deduplicate and sort
awk 'NF' "${combined_reqs}" | sort -u -o "${combined_reqs}"

# Install if non-empty
if [[ -s "${combined_reqs}" ]]; then
  echo "Installing Python libs from ${combined_reqs}"
  pip install --no-cache-dir -r "${combined_reqs}"
else
  echo "No Python dependencies found – skipping pip install"
fi

# -------------------- Cleanup --------------------
rm -rf "$TMP_ADDONS_DIR"
echo "INFO: extra-addons ready under: $ADDONS_DIR"
