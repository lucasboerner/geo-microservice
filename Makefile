# geo-microservice — convenience targets.
# `make smoke` black-box tests a running gateway (start it with `docker compose up`).
SHELL := /usr/bin/env bash

BASE_URL ?= http://localhost:8080
API_KEY  ?=

.DEFAULT_GOAL := help
.PHONY: help smoke

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

smoke: ## Smoke-test /health, /geocode and /route (vars: BASE_URL, API_KEY)
	@BASE_URL="$(BASE_URL)" API_KEY="$(API_KEY)" ./bin/smoke.sh
