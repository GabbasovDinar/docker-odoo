# syntax=docker/dockerfile:1.6

ARG PYTHON_IMAGE=python:3.12-slim-bookworm

FROM ${PYTHON_IMAGE} AS odoo-src

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]
ENV LANG=C.UTF-8

# ---------------------------------------------------------------------------
# Core system packages
# ---------------------------------------------------------------------------

RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
        curl \
        python3-pip \
        libldap2-dev \
        libpq-dev \
        libsasl2-dev \
        rsync \
        python3-dev \
        python3-virtualenv \
        build-essential \
        gnupg \
        npm \
        git \
        libxml2-dev \
        libxslt1-dev \
        libz-dev \
        libxmlsec1-dev \
        libcups2-dev \
        swig \
        libffi-dev \
        pkg-config \
        libcairo2-dev \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# wkhtmltopdf drop-in client
# ---------------------------------------------------------------------------

ARG KWKHTMLTOPDF_CLIENT_REF=1.0

RUN curl -fsSL \
        "https://raw.githubusercontent.com/acsone/kwkhtmltopdf/${KWKHTMLTOPDF_CLIENT_REF}/client/python/kwkhtmltopdf_client.py" \
        -o /usr/local/bin/wkhtmltopdf \
    && chmod +x /usr/local/bin/wkhtmltopdf

# ---------------------------------------------------------------------------
# PostgreSQL client
# ---------------------------------------------------------------------------

    ARG POSTGRES_VERSION=16

    RUN install -d -m 0755 /usr/share/keyrings \
        && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
            | gpg --dearmor -o /usr/share/keyrings/postgres.gpg \
        && echo \
            "deb [signed-by=/usr/share/keyrings/postgres.gpg] http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
            > /etc/apt/sources.list.d/pgclient.list \
        && apt-get update -qq \
        && DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
            postgresql-client-${POSTGRES_VERSION} \
        && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Node dependencies
# ---------------------------------------------------------------------------

RUN npm install -g rtlcss


# ---------------------------------------------------------------------------
# Python virtualenv
# ---------------------------------------------------------------------------

ENV VIRTUAL_ENV=/opt/odoo-venv

RUN python3 -m venv "${VIRTUAL_ENV}"

ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"


# ---------------------------------------------------------------------------
# Odoo Community source
# ---------------------------------------------------------------------------

ARG ODOO_DIR=/opt/odoo

ARG ODOO_REPO=https://github.com/odoo/odoo.git
ARG ODOO_REF=18.0

# Git authentication configuration.
# Actual tokens are passed only through BuildKit secrets below.
ARG GIT_HOST=
ARG GIT_USER=oauth2
ARG GITHUB_HOST=github.com
ARG GITLAB_HOST=gitlab.com
ARG GITHUB_USER=x-access-token
ARG GITLAB_USER=oauth2

COPY base/scripts/git-auth.sh /usr/local/lib/odoo/git-auth.sh
COPY base/scripts/odoo-source.sh /usr/local/bin/odoo-source

RUN chmod +x /usr/local/bin/odoo-source

RUN --mount=type=secret,id=github_token,required=false \
    --mount=type=secret,id=gitlab_token,required=false \
    --mount=type=secret,id=git_token,required=false \
    GITHUB_TOKEN="$(cat /run/secrets/github_token 2>/dev/null || true)" \
    GITLAB_TOKEN="$(cat /run/secrets/gitlab_token 2>/dev/null || true)" \
    GIT_TOKEN="$(cat /run/secrets/git_token 2>/dev/null || true)" \
    /usr/local/bin/odoo-source

# ---------------------------------------------------------------------------
# Odoo Python dependencies
# ---------------------------------------------------------------------------

RUN pip install --no-cache-dir \
-r "${ODOO_DIR}/requirements.txt"

# ---------------------------------------------------------------------------
# Odoo system user
# ---------------------------------------------------------------------------

ARG DOCKER_ODOO_UID=9999
ARG DOCKER_ODOO_GID=9999

RUN groupadd --gid "${DOCKER_ODOO_GID}" odoo \
    && useradd \
        --uid "${DOCKER_ODOO_UID}" \
        --gid "${DOCKER_ODOO_GID}" \
        --create-home \
        --shell /bin/bash \
        odoo


# ---------------------------------------------------------------------------
# Install Odoo
# ---------------------------------------------------------------------------

RUN pip install --no-cache-dir \
    -e "${ODOO_DIR}" \
    --config-setting=editable-mode=compat


# ---------------------------------------------------------------------------
# Scripts and configuration
# ---------------------------------------------------------------------------

RUN mkdir -p \
    /usr/local/share/odoo/tmpl \
    /usr/local/share/odoo/manifests \
    /run/odoo

COPY base/scripts/wait-for-psql.py /usr/local/bin/wait-for-psql.py
COPY base/scripts/odoorc.py         /usr/local/bin/odoorc.py
COPY base/scripts/odoo-debug.py     /usr/local/bin/odoo-debug.py
COPY base/scripts/odoo-test.sh      /usr/local/bin/odoo-test
COPY base/scripts/entrypoint.sh     /
COPY base/scripts/extra-addons.sh   /

COPY base/config/odoo.conf.tpl \
    /usr/local/share/odoo/tmpl/odoo.conf.tpl

COPY base/manifests/enterprise.yml \
    /usr/local/share/odoo/manifests/enterprise.yml

RUN chmod +x \
        /usr/local/bin/wait-for-psql.py \
        /usr/local/bin/wkhtmltopdf \
        /usr/local/bin/odoo-debug.py \
        /usr/local/bin/odoo-test \
        /entrypoint.sh \
        /extra-addons.sh \
    && chown -R odoo:odoo /run/odoo

# ---------------------------------------------------------------------------
# Odoo filesystem/configuration
# ---------------------------------------------------------------------------

ARG ODOO_RC=/etc/odoo.conf
ARG ODOO_DATA_DIR=/var/lib/odoo
ARG ODOO_LOG_DIR=/var/log/odoo

ARG ADDONS_DIR=${ODOO_DIR}/addons
ARG EXTRA_ADDONS_DIR=/opt/extra-addons
ARG ODOO_EE_ADDONS_DIR=/opt/enterprise-addons

RUN printf \
        "[options]\ndata_dir = %s\n" \
        "${ODOO_DATA_DIR}" \
        > "${ODOO_RC}" \
    && chown odoo:odoo "${ODOO_RC}"

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

RUN mkdir -p \
        "${ODOO_DATA_DIR}" \
        "${EXTRA_ADDONS_DIR}" \
        "${ODOO_EE_ADDONS_DIR}" \
        "${ADDONS_DIR}" \
        "${ODOO_LOG_DIR}" \
        "${TMP_ADDONS_DIR}" \
    && chown -R odoo:odoo \
        "${ODOO_DATA_DIR}" \
        "${EXTRA_ADDONS_DIR}" \
        "${ODOO_EE_ADDONS_DIR}" \
        "${ADDONS_DIR}" \
        "${ODOO_LOG_DIR}"


# ---------------------------------------------------------------------------
# Tools required for extra addons / Enterprise installation
# ---------------------------------------------------------------------------

COPY base/requirements.txt /tmp/requirements.txt

RUN pip install --no-cache-dir -r /tmp/requirements.txt \
    && rm -f /tmp/requirements.txt

# ---------------------------------------------------------------------------
# Odoo Enterprise
# ---------------------------------------------------------------------------

ARG ODOO_EDITION=ce

ARG ODOO_EE_VERSION=18.0
ARG ODOO_ENTERPRISE_REF=${ODOO_EE_VERSION}

ARG ODOO_ENTERPRISE_REPO=https://github.com/odoo/enterprise.git

ARG ODOO_EE_GIT_USER=x-access-token
ARG ODOO_EE_GIT_HOST=github.com

RUN --mount=type=secret,id=odoo_ee_git_token,required=false \
    if [ "${ODOO_EDITION}" = "ee" ]; then \
        ODOO_EE_GIT_TOKEN="$(cat /run/secrets/odoo_ee_git_token 2>/dev/null || true)"; \
        echo "Installing Odoo Enterprise..."; \
        /extra-addons.sh \
            --addons-file=/usr/local/share/odoo/manifests/enterprise.yml \
            --addons-dir="${ODOO_EE_ADDONS_DIR}" \
            --git-user="${ODOO_EE_GIT_USER}" \
            --git-token="${ODOO_EE_GIT_TOKEN}" \
            --git-host="${ODOO_EE_GIT_HOST}"; \
    fi


# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------

VOLUME ["${ODOO_DATA_DIR}"]

EXPOSE 8069 8071 8072

USER odoo

ENTRYPOINT ["/entrypoint.sh"]
CMD ["odoo"]
