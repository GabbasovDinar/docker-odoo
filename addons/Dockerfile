# syntax=docker/dockerfile:1.6

ARG ODOO_EDITION=ce
ARG ODOO_VERSION=18.0
ARG BASE_IMAGE=odoo-core-${ODOO_EDITION}:${ODOO_VERSION}
FROM ${BASE_IMAGE}

ARG ADDONS_YML=addons/addons.yml
COPY ${ADDONS_YML} /usr/local/share/odoo/manifests/addons.yml

USER root
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# --- Install Extra Requirements
COPY addons/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt

# --- Install Extra Addons
RUN mkdir -p ${EXTRA_ADDONS_DIR} && chown odoo ${EXTRA_ADDONS_DIR} \
    && /extra-addons.sh \
        --addons-file=/usr/local/share/odoo/manifests/addons.yml \
        --addons-dir=${EXTRA_ADDONS_DIR} \
        --env-file=${ODOO_ENV_FILE}

# Set default user when running the container
USER odoo
