ENV_FILE ?= .env
COMPOSE_PROJECT_NAME ?= docker-odoo
MODE ?= prod
COMPOSE_FILES ?= -f docker-compose.yml $(if $(filter dev,$(MODE)),-f docker-compose.dev.yml) $(if $(filter test,$(MODE)),-f docker-compose.test.yml)
MIGRATION_LOG ?= migration.log

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

COMPOSE = COMPOSE_PROJECT_NAME=$(COMPOSE_PROJECT_NAME) ENV_FILE=$(ENV_FILE) docker compose --env-file $(ENV_FILE) $(COMPOSE_FILES)
TEST_RUN_ENV = \
	-e ODOO_TEST_DB="$(TEST_DB)" \
	-e ODOO_TEST_MODULES="$(TEST_MODULES)" \
	-e ODOO_TEST_TAGS="$(TEST_TAGS)" \
	-e ODOO_TEST_KEEP_DB="$(TEST_KEEP_DB)" \
	-e ODOO_TEST_DROP_FAILED_DB="$(TEST_DROP_FAILED_DB)"

.PHONY: check-env
check-env:
	@if [ ! -f "$(ENV_FILE)" ]; then \
		if [ "$(ENV_FILE)" = ".env" ]; then \
			printf "Missing .env. Creating from .env.example\n"; \
			cp .env.example .env; \
		else \
			printf "Missing env file: %s\n" "$(ENV_FILE)" >&2; \
			exit 1; \
		fi; \
	fi

.PHONY: help
help: ## Show available targets
	@printf "Usage: make <target> [MODE=prod|dev|test] [ENV_FILE=.env] [COMPOSE_PROJECT_NAME=docker-odoo]\n\n"
	@awk 'BEGIN {FS = ":.*?## "}; /^[a-zA-Z0-9_.-]+:.*?## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST) | sort

.PHONY: env
env: ## Show the resolved make/compose environment
	@printf "MODE=%s\n" "$(MODE)"
	@printf "ENV_FILE=%s\n" "$(ENV_FILE)"
	@printf "COMPOSE_PROJECT_NAME=%s\n" "$(COMPOSE_PROJECT_NAME)"
	@printf "COMPOSE_FILES=%s\n" "$(COMPOSE_FILES)"

.PHONY: build-base
build-base: check-env ## Build the reusable Odoo base image
	$(COMPOSE) --profile build build $(BASE_SERVICE)

.PHONY: build-addons
build-addons: check-env ## Build the project addons layer
	$(COMPOSE) build $(ADDONS_SERVICE)

.PHONY: init
init: check-env build-base build-addons ## Build the base and addons images

.PHONY: build
build: init

.PHONY: rebuild-addons
rebuild-addons: check-env ## Rebuild the addons image without cache
	$(COMPOSE) build --no-cache $(ADDONS_SERVICE)

.PHONY: pull
pull: check-env ## Pull runtime images
	$(COMPOSE) pull

.PHONY: up
up: check-env ## Start the stack
	$(COMPOSE) up -d

.PHONY: prod
prod: MODE=prod
prod: up ## Start the stack in production mode

.PHONY: dev
dev: MODE=dev
dev: up ## Start the stack in development mode

.PHONY: test
test: MODE=test
test: check-env ## Run tests for local addons
test:
	$(COMPOSE) run --rm $(TEST_RUN_ENV) $(ADDONS_SERVICE) odoo-test $(ARGS)

.PHONY: migrate
migrate: check-env ## Run OpenUpgrade in background and follow migration logs
	@rm -f "$(MIGRATION_LOG)"
	@set -u -o pipefail; \
		start_ts="$$(date +%s)"; \
		printf "Stopping the normal Odoo service before migration...\n"; \
		$(COMPOSE) stop $(ADDONS_SERVICE) || true; \
		printf "Starting OpenUpgrade migration...\n"; \
		if ! container_id="$$( \
			$(COMPOSE) run -d --rm $(ADDONS_SERVICE) openupgrade \
		)"; then \
			printf "ERROR: failed to start migration container\n" \
				| tee -a "$(MIGRATION_LOG)"; \
			exit 1; \
		fi; \
		printf "Migration container: %s\n" "$$container_id"; \
		printf "Following migration logs...\n\n"; \
		status_file="$$(mktemp)"; \
		trap 'rm -f "$$status_file"' EXIT; \
		docker wait "$$container_id" > "$$status_file" & \
		wait_pid="$$!"; \
		docker logs -f "$$container_id" 2>&1 \
			| tee "$(MIGRATION_LOG)" || true; \
		wait "$$wait_pid" || true; \
		status="$$(cat "$$status_file" 2>/dev/null || printf '1')"; \
		end_ts="$$(date +%s)"; \
		duration="$$(($$end_ts - $$start_ts))"; \
		hours="$$(($$duration / 3600))"; \
		minutes="$$(($$duration % 3600 / 60))"; \
		seconds="$$(($$duration % 60))"; \
		printf "\n"; \
		if [ "$$status" -eq 0 ]; then \
			printf "Migration completed successfully (exit code 0).\n" \
				| tee -a "$(MIGRATION_LOG)"; \
		else \
			printf "Migration failed (exit code %s).\n" "$$status" \
				| tee -a "$(MIGRATION_LOG)"; \
		fi; \
		printf "Migration duration: %02d:%02d:%02d\n" \
			"$$hours" "$$minutes" "$$seconds" \
			| tee -a "$(MIGRATION_LOG)"; \
		exit "$$status"

.PHONY: start
start: up

.PHONY: stop
stop: check-env ## Stop the stack without removing containers
	$(COMPOSE) stop

.PHONY: restart
restart: check-env ## Restart the stack
	$(COMPOSE) restart

.PHONY: down
down: check-env ## Stop and remove containers
	$(COMPOSE) down --remove-orphans

.PHONY: down-v
down-v: check-env ## Stop and remove containers including volumes
	$(COMPOSE) down -v --remove-orphans

.PHONY: logs
logs: check-env ## Follow logs
	$(COMPOSE) logs -f --tail=200

.PHONY: log-odoo
log-odoo: check-env ## Follow Odoo logs
	$(COMPOSE) logs -f --tail=200 $(ADDONS_SERVICE)

.PHONY: log-db
log-db: check-env ## Follow PostgreSQL logs
	$(COMPOSE) logs -f --tail=200 $(DB_SERVICE)

.PHONY: log-redis
log-redis: check-env ## Follow Redis logs
	$(COMPOSE) logs -f --tail=200 $(REDIS_SERVICE)

.PHONY: log-caddy
log-caddy: check-env ## Follow Caddy logs
	$(COMPOSE) logs -f --tail=200 $(CADDY_SERVICE)

.PHONY: log-wkhtmltopdf
log-wkhtmltopdf: check-env ## Follow kwkhtmltopdf logs
	$(COMPOSE) logs -f --tail=200 $(WKHTMLTOPDF_SERVICE)

.PHONY: ps
ps: check-env ## Show service status
	$(COMPOSE) ps

.PHONY: sh
sh: check-env ## Open a shell in the Odoo container
	$(COMPOSE) exec $(ADDONS_SERVICE) bash || $(COMPOSE) run --rm $(ADDONS_SERVICE) bash

.PHONY: odoo-shell
odoo-shell: check-env ## Open odoo shell without starting HTTP
	$(COMPOSE) exec $(ADDONS_SERVICE) odoo shell -c $${ODOO_RC:-/etc/odoo.conf} --no-http

.PHONY: psql
psql: check-env ## Open a psql session against PostgreSQL
	$(COMPOSE) exec $(DB_SERVICE) psql -U $${DB_USER:-odoo} -d $${DB_NAME:-postgres} || $(COMPOSE) run --rm $(DB_SERVICE) psql -U $${DB_USER:-odoo} -d $${DB_NAME:-postgres}

.PHONY: config
config: check-env ## Render the effective Compose configuration
	$(COMPOSE) config

.PHONY: backup
backup: check-env ## Create a DB + filestore backup under backups/<timestamp>
	COMPOSE_PROJECT_NAME="$(COMPOSE_PROJECT_NAME)" \
	ENV_FILE="$(ENV_FILE)" \
	COMPOSE_FILES="$(COMPOSE_FILES)" \
	./scripts/backup.sh $(NAME)

.PHONY: restore
restore: check-env ## Restore DB + filestore from backups/<name> (pass BACKUP=backups/<name>)
	@test -n "$(BACKUP)" || { printf "Usage: make restore BACKUP=backups/<name>\n" >&2; exit 2; }
	COMPOSE_PROJECT_NAME="$(COMPOSE_PROJECT_NAME)" \
	ENV_FILE="$(ENV_FILE)" \
	COMPOSE_FILES="$(COMPOSE_FILES)" \
	./scripts/restore.sh "$(BACKUP)"

.PHONY: prune
prune: ## Prune the Docker build cache
	docker builder prune -f
