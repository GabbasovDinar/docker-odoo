COMPOSE ?= docker compose -f docker-compose.yml
SHELL := /bin/bash
.DEFAULT_GOAL := help

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

BASE_SERVICE ?= odoo-core
ADDONS_SERVICE ?= odoo
DB_SERVICE ?= db
CADDY_SERVICE ?= caddy
WKHTMLTOPDF_SERVICE ?= kwkhtmltopdf
REDIS_SERVICE ?= redis

.PHONY: check-env
check-env:
	@test -f .env || { printf "Missing .env. Creating from .env.example\n"; cp .env.example .env; }

.PHONY: help
help: ## Show available targets
	@printf "Usage: make <target>\n\n"
	@awk 'BEGIN {FS = ":.*?## "}; /^[a-zA-Z0-9_.-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

.PHONY: build-base
build-base: check-env ## Build the reusable Odoo base image
	$(COMPOSE) --profile build build $(BASE_SERVICE)

.PHONY: build-addons
build-addons: check-env ## Build the project addons layer
	$(COMPOSE) build $(ADDONS_SERVICE)

.PHONY: init
init: check-env build-base build-addons ## Fully prepare the stack: validate .env and build base + addons images

.PHONY: build
build: init

.PHONY: rebuild-addons
rebuild-addons: ## Rebuild the addons image without using cache
	$(COMPOSE) build --no-cache $(ADDONS_SERVICE)

.PHONY: pull
pull:
	$(COMPOSE) pull

.PHONY: start
start: check-env ## Start all runtime services in detached mode
	$(COMPOSE) up -d

.PHONY: up
up: start

.PHONY: stop
stop: ## Stop all running services without removing containers or volumes
	$(COMPOSE) stop

.PHONY: restart
restart: ## Restart all services
	$(COMPOSE) restart

.PHONY: down
down: ## Stop services and remove containers
	$(COMPOSE) down --remove-orphans

.PHONY: down-v
down-v: ## Stop services and remove containers, networks and volumes
	$(COMPOSE) down -v --remove-orphans

.PHONY: logs
logs: ## Follow logs from all services
	$(COMPOSE) logs -f --tail=200

.PHONY: log-odoo
log-odoo: ## Follow Odoo logs
	$(COMPOSE) logs -f --tail=200 $(ADDONS_SERVICE)

.PHONY: log-db
log-db: ## Follow PostgreSQL logs
	$(COMPOSE) logs -f --tail=200 $(DB_SERVICE)

.PHONY: logs-db
logs-db: log-db

.PHONY: log-caddy
log-caddy: ## Follow Caddy logs
	$(COMPOSE) logs -f --tail=200 $(CADDY_SERVICE)

.PHONY: log-wkhtmltopdf
log-wkhtmltopdf: ## Follow kwkhtmltopdf logs
	$(COMPOSE) logs -f --tail=200 $(WKHTMLTOPDF_SERVICE)

.PHONY: log-redis
log-redis: ## Follow Redis logs
	$(COMPOSE) logs -f --tail=200 $(REDIS_SERVICE)

.PHONY: ps
ps: ## Show service status
	$(COMPOSE) ps

.PHONY: sh
sh: ## Shell into the Odoo container (reuse or run)
	$(COMPOSE) exec $(ADDONS_SERVICE) bash || $(COMPOSE) run --rm $(ADDONS_SERVICE) bash

.PHONY: odoo-shell
odoo-shell: ## Open Odoo shell without starting HTTP
	$(COMPOSE) exec $(ADDONS_SERVICE) odoo shell -c $${ODOO_RC:-/etc/odoo.conf} --no-http

.PHONY: psql
psql: ## Open psql session against PostgreSQL
	$(COMPOSE) exec $(DB_SERVICE) psql -U $${DB_USER:-odoo} -d $${DB_NAME:-postgres} || $(COMPOSE) run --rm $(DB_SERVICE) psql -U $${DB_USER:-odoo} -d $${DB_NAME:-postgres}

.PHONY: config
config: ## Render the effective Compose configuration
	$(COMPOSE) config

.PHONY: prune
prune:
	docker builder prune -f
