# syntax=docker/dockerfile:1.6

ARG ODOO_EDITION=ce
ARG ODOO_VERSION=18.0
ARG BASE_IMAGE=odoo-core-${ODOO_EDITION}:${ODOO_VERSION}
FROM ${BASE_IMAGE}

ARG ADDONS_YML=addons/addons.yml

ARG GIT_HOST=
ARG GIT_USER=oauth2
ARG GITHUB_HOST=github.com
ARG GITLAB_HOST=gitlab.com
ARG GITHUB_USER=x-access-token
ARG GITLAB_USER=oauth2

COPY ${ADDONS_YML} /usr/local/share/odoo/manifests/addons.yml

USER root
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# --- Install Extra Requirements
COPY addons/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt

# --- Install Extra Addons
RUN --mount=type=secret,id=github_token,required=false \
    --mount=type=secret,id=gitlab_token,required=false \
    --mount=type=secret,id=git_token,required=false \
    GITHUB_TOKEN="$(cat /run/secrets/github_token 2>/dev/null || true)"; \
    GITLAB_TOKEN="$(cat /run/secrets/gitlab_token 2>/dev/null || true)"; \
    GIT_TOKEN="$(cat /run/secrets/git_token 2>/dev/null || true)"; \
    mkdir -p "${EXTRA_ADDONS_DIR}" \
    && chown odoo:odoo "${EXTRA_ADDONS_DIR}" \
    && /extra-addons.sh \
        --addons-file=/usr/local/share/odoo/manifests/addons.yml \
        --addons-dir="${EXTRA_ADDONS_DIR}" \
        --github-user="${GITHUB_USER}" \
        --github-token="${GITHUB_TOKEN}" \
        --github-host="${GITHUB_HOST}" \
        --gitlab-user="${GITLAB_USER}" \
        --gitlab-token="${GITLAB_TOKEN}" \
        --gitlab-host="${GITLAB_HOST}" \
        --git-user="${GIT_USER}" \
        --git-token="${GIT_TOKEN}" \
        --git-host="${GIT_HOST}"

# Set default user when running the container
USER odoo
