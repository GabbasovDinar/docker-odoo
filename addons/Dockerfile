# syntax=docker/dockerfile:1.6

ARG ODOO_EDITION=ce
ARG ODOO_VERSION=18.0
ARG BASE_IMAGE=odoo-core-${ODOO_EDITION}:${ODOO_VERSION}
FROM ${BASE_IMAGE}

ARG ADDONS_YML=addons/addons.yml
ARG GIT_HOST
ARG GIT_USER
ARG GITHUB_HOST
ARG GITLAB_HOST
ARG GITHUB_USER
ARG GITLAB_USER

COPY ${ADDONS_YML} /usr/local/share/odoo/manifests/addons.yml

USER root
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# --- Install Extra Requirements
COPY addons/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt

# --- Install Extra Addons
RUN --mount=type=secret,id=github_token,env=GITHUB_TOKEN \
    --mount=type=secret,id=gitlab_token,env=GITLAB_TOKEN \
    --mount=type=secret,id=git_token,env=GIT_TOKEN \
    mkdir -p ${EXTRA_ADDONS_DIR} && chown odoo ${EXTRA_ADDONS_DIR} \
    && /extra-addons.sh \
        --addons-file=/usr/local/share/odoo/manifests/addons.yml \
        --addons-dir=${EXTRA_ADDONS_DIR}

# Set default user when running the container
USER odoo
