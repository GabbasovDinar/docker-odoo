COMPOSE ?= docker compose -f docker-compose.yml
SHELL := /bin/bash
.DEFAULT_GOAL := help

export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

BASE_SERVICE ?= odoo-core
ADDONS_SERVICE ?= odoo

.PHONY: help
help: ## Show available targets
	@printf "Usage: make <target>\n\n"
	@awk 'BEGIN {FS = ":.*?## "}; /^[a-zA-Z0-9_.-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

.PHONY: build-base
build-base: ## Build the reusable Odoo base image
	$(COMPOSE) --profile build build $(BASE_SERVICE)

.PHONY: build-addons
build-addons: ## Build the project addons layer
	$(COMPOSE) build $(ADDONS_SERVICE)

.PHONY: build
build: build-base build-addons ## Build both images (base and addons)

.PHONY: build-ce
build-ce: ## Build Community Edition images
	@$(MAKE) build ODOO_EDITION=ce

.PHONY: build-ee
build-ee: ## Build Enterprise Edition images (requires EE credentials)
	@$(MAKE) build ODOO_EDITION=ee

.PHONY: rebuild-addons
rebuild-addons: ## Rebuild the addons image without using cache
	$(COMPOSE) build --no-cache $(ADDONS_SERVICE)

.PHONY: pull
pull: ## Pull the latest service images
	$(COMPOSE) pull

.PHONY: up
up: ## Start the stack in detached mode (build on demand)
	$(COMPOSE) up -d --build

.PHONY: start
start: up ## Alias for `make up`

.PHONY: stop
stop: ## Stop running services without removing resources
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
logs: ## Tail Odoo logs
	$(COMPOSE) logs -f --tail=200 $(ADDONS_SERVICE)

.PHONY: logs-db
logs-db: ## Tail PostgreSQL logs
	$(COMPOSE) logs -f --tail=200 db

.PHONY: ps
ps: ## Show service status
	$(COMPOSE) ps

.PHONY: sh
sh: ## Shell into the Odoo container (reuse or run)
	$(COMPOSE) exec $(ADDONS_SERVICE) bash || $(COMPOSE) run --rm $(ADDONS_SERVICE) bash

.PHONY: psql
psql: ## Open psql session against PostgreSQL
	$(COMPOSE) exec db psql -U $${DB_USER:-odoo} -d $${DB_NAME:-postgres} || $(COMPOSE) run --rm db psql -U $${DB_USER:-odoo} -d $${DB_NAME:-postgres}

.PHONY: config
config: ## Render the effective Compose configuration
	$(COMPOSE) config

.PHONY: prune
prune: ## Prune Docker builder cache
	docker builder prune -f
