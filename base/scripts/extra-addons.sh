#!/usr/bin/env bash
set -euo pipefail

# -------------------- Defaults --------------------
: "${TMP_ADDONS_DIR:=/tmp/getaddons}"

# shellcheck source=base/scripts/git-auth.sh
source /usr/local/lib/odoo/git-auth.sh

ADDONS_FILE=""

# -------------------- Args --------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --addons-file)       ADDONS_FILE="${2:-}"; shift 2 ;;
    --addons-file=*)     ADDONS_FILE="${1#*=}"; shift ;;
    --addons-dir)        ADDONS_DIR="${2:-}"; shift 2 ;;
    --addons-dir=*)      ADDONS_DIR="${1#*=}"; shift ;;
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

# -------------------- Git authentication --------------------
trap git_auth_cleanup EXIT
git_auth_setup

# -------------------- Prepare --------------------
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
  gitaggregate -c "$ADDONS_YML" --expand-env
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
  echo "No Python dependencies found - skipping pip install"
fi

# -------------------- Cleanup --------------------
rm -rf "$TMP_ADDONS_DIR"
echo "INFO: extra-addons ready under: $ADDONS_DIR"
