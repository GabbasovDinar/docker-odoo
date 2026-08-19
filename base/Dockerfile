# syntax=docker/dockerfile:1.6

ARG PYTHON_IMAGE=python:3.12-slim-bookworm

FROM ${PYTHON_IMAGE} AS odoo-src

# --- Odoo variables
ARG ODOO_RC=/etc/odoo.conf
ARG ODOO_DIR=/opt/odoo
ARG ODOO_DATA_DIR=/var/lib/odoo
ARG ODOO_LOG_DIR=/var/log/odoo
ARG ADDONS_DIR=${ODOO_DIR}/addons
ARG EXTRA_ADDONS_DIR=/opt/extra-addons
ARG DOCKER_ODOO_UID=9999
ARG DOCKER_ODOO_GID=9999
# ce or ee
ARG ODOO_EDITION=ce
# CE or EE version or tags
ARG ODOO_CE_VERSION=17.0
ARG ODOO_CE_REF=
ARG ODOO_EE_VERSION=17.0
ARG KWKHTMLTOPDF_CLIENT_REF=1.0
# --- Enterprise variables
ARG ODOO_EE_ADDONS_DIR=/opt/enterprise-addons
ARG ODOO_ENTERPRISE_REPO=https://github.com/odoo/enterprise.git
# Fallback build arg for manual builds. Prefer the BuildKit secret mount
# "odoo_ee_git_token" configured in docker-compose.yml.
ARG ODOO_EE_GIT_USER=x-access-token
ARG ODOO_EE_GIT_TOKEN=
ARG ODOO_EE_GIT_HOST=github.com
# --- PostgreSQL variables
ARG POSTGRES_VERSION=16
# --- Target architecture
ARG TARGETARCH

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ENV LANG=C.UTF-8

# --- Core system packages
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends curl python3-pip libldap2-dev libpq-dev libsasl2-dev rsync \
    python3-dev python3-virtualenv build-essential gnupg npm git \
    libxml2-dev \
    libxslt1-dev \
    libz-dev \
    libxmlsec1-dev \
    libcups2-dev \
    swig \
    libffi-dev \
    pkg-config \
    libcairo2-dev && \
    rm -rf /var/lib/apt/lists/*

# --- wkhtmltopdf drop-in client for the external kwkhtmltopdf service
RUN curl -fsSL "https://raw.githubusercontent.com/acsone/kwkhtmltopdf/${KWKHTMLTOPDF_CLIENT_REF}/client/python/kwkhtmltopdf_client.py" \
        -o /usr/local/bin/wkhtmltopdf \
    && chmod +x /usr/local/bin/wkhtmltopdf

# --- PostgreSQL client
RUN install -d -m 0755 /usr/share/keyrings \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /usr/share/keyrings/postgres.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/postgres.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
        > /etc/apt/sources.list.d/pgclient.list \
    && apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends postgresql-client-${POSTGRES_VERSION} \
    && rm -rf /var/lib/apt/lists/*

# --- Node deps
RUN npm install -g rtlcss

# --- venv
ENV VIRTUAL_ENV=/opt/odoo-venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

# --- Install odoo python requirements
RUN ODOO_SOURCE_HEAD="${ODOO_CE_REF:-${ODOO_CE_VERSION}}" \
    && curl -fsSL "https://raw.githubusercontent.com/odoo/odoo/${ODOO_SOURCE_HEAD}/requirements.txt" -o /tmp/odoo-req.txt \
    && pip install --no-cache-dir -r /tmp/odoo-req.txt \
    && rm -f /tmp/odoo-req.txt

# --- User
RUN groupadd --gid ${DOCKER_ODOO_GID} odoo && useradd odoo -u ${DOCKER_ODOO_UID} -g ${DOCKER_ODOO_GID} -m -s /bin/bash

# --- Source Odoo
ARG ODOO_HEAD=
RUN mkdir /tmp/getodoo \
    && ODOO_SOURCE_HEAD="${ODOO_HEAD:-${ODOO_CE_REF:-${ODOO_CE_VERSION}}}" \
    && (curl -fsSL "https://github.com/odoo/odoo/tarball/${ODOO_SOURCE_HEAD}" | tar -C /tmp/getodoo -xz) \
    && mv /tmp/getodoo/* ${ODOO_DIR} \
    && rmdir /tmp/getodoo

# --- Install Odoo
RUN pip install --no-cache-dir -e ${ODOO_DIR} --config-setting=editable-mode=compat \
    && mv "${VIRTUAL_ENV}/bin/odoo" "${VIRTUAL_ENV}/bin/odoo-real"

# --- Copy scripts and Odoo configuration files
RUN mkdir -p /usr/local/share/odoo/tmpl /usr/local/share/odoo/manifests /run/odoo

COPY base/scripts/wait-for-psql.py /usr/local/bin/wait-for-psql.py
COPY base/scripts/odoorc.py         /usr/local/bin/odoorc.py
COPY base/scripts/odoo-debug.py     /usr/local/bin/odoo-debug.py
COPY base/scripts/odoo-launcher.sh  /opt/odoo-venv/bin/odoo
COPY base/scripts/entrypoint.sh     /
COPY base/scripts/extra-addons.sh   /
COPY base/config/odoo.conf.tpl      /usr/local/share/odoo/tmpl/odoo.conf.tpl
COPY base/manifests/enterprise.yml  /usr/local/share/odoo/manifests/enterprise.yml

RUN chmod +x /usr/local/bin/wait-for-psql.py /usr/local/bin/wkhtmltopdf /usr/local/bin/odoo-debug.py /opt/odoo-venv/bin/odoo /entrypoint.sh /extra-addons.sh && chown -R odoo:odoo /run/odoo

# --- Create base odoo config file
RUN printf "[options]\ndata_dir = %s\n" "${ODOO_DATA_DIR}" > "${ODOO_RC}" && chown odoo:odoo "${ODOO_RC}"

# --- Create directories for extra addons and filestore, set ownership to `odoo`
ENV ODOO_RC=${ODOO_RC} \
    ODOO_RC_TEMPLATE=/usr/local/share/odoo/tmpl/odoo.conf.tpl \
    ODOO_LOG_DIR=${ODOO_LOG_DIR} \
    ODOO_ENV_FILE=/run/odoo/.env \
    ADDONS_DIR=${ADDONS_DIR} \
    EXTRA_ADDONS_DIR=${EXTRA_ADDONS_DIR} \
    ODOO_EE_ADDONS_DIR=${ODOO_EE_ADDONS_DIR} \
    KWKHTMLTOPDF_SERVER_URL=http://kwkhtmltopdf:8080 \
    TMP_ADDONS_DIR=/tmp/getaddons \
    HOME=${ODOO_DATA_DIR}

RUN mkdir -p "${ODOO_DATA_DIR}" "${EXTRA_ADDONS_DIR}" "${ODOO_EE_ADDONS_DIR}" "${ADDONS_DIR}" "${ODOO_LOG_DIR}" "${TMP_ADDONS_DIR}" \
    && chown -R odoo:odoo "${ODOO_DATA_DIR}" "${EXTRA_ADDONS_DIR}" "${ODOO_EE_ADDONS_DIR}" "${ADDONS_DIR}" "${ODOO_LOG_DIR}"

# Install tools needed for extra addons and odoo enterprise installation
COPY base/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt

# Install Odoo EE
ARG ODOO_ENTERPRISE_REF=${ODOO_EE_VERSION}
RUN --mount=type=secret,id=odoo_ee_git_token,required=false \
    if [ "$ODOO_EDITION" = "ee" ]; then \
      if [ -f /run/secrets/odoo_ee_git_token ]; then \
        ODOO_EE_GIT_TOKEN="$(cat /run/secrets/odoo_ee_git_token)"; \
      fi; \
      echo "Installing Odoo Enterprise..." && \
      /extra-addons.sh \
          --addons-file=/usr/local/share/odoo/manifests/enterprise.yml \
          --addons-dir="${ODOO_EE_ADDONS_DIR}" \
          --git-user="${ODOO_EE_GIT_USER}" \
          --git-token="${ODOO_EE_GIT_TOKEN}" \
          --git-host="${ODOO_EE_GIT_HOST}"; \
    fi

# Expose filestore
VOLUME ["${ODOO_DATA_DIR}"]

# Expose Odoo services
EXPOSE 8069 8071 8072

# Set default user when running the container
USER odoo

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
