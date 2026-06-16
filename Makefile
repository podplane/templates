# Podplane <https://podplane.dev>
# Copyright 2026 Nadrama Pty Ltd
# SPDX-License-Identifier: Apache-2.0

CHARTS := $(patsubst %/Chart.yaml,%,$(wildcard */Chart.yaml))
JSON_FILES := $(shell find manifests -name '*.json' -type f 2>/dev/null | sort)
YAML_FILES := $(shell find . -path './.git' -prune -o -path '*/templates/*.yaml' -prune -o -type f \( -name '*.yaml' -o -name '*.yml' \) -print | sort)

.DEFAULT_GOAL := help

.PHONY: help setup fmt check lint validate update-manifests precommit

help: ## Show available targets
	@echo "Usage: make <target>"
	@awk 'BEGIN {FS = ":.*?## "} /^##@/ {printf "\n\033[1m%s\033[0m\n", substr($$0, 5)} /^[a-zA-Z_-]+:.*?## / {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

setup: ## Install git hooks
	@mkdir -p .git/hooks
	@printf '%s\n' '#!/usr/bin/env bash' 'set -eo pipefail' 'echo "Running pre-commit checks..."' 'make precommit' 'echo "Pre-commit checks passed."' > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "Installed .git/hooks/pre-commit"

fmt: ## Format JSON files
	@command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed"; exit 1; }
	@echo "Formatting JSON files..."
	@for file in $(JSON_FILES); do \
		tmp="$$(mktemp)"; \
		jq . "$$file" > "$$tmp"; \
		mv "$$tmp" "$$file"; \
	done

check: ## Check JSON formatting and YAML parseability
	@command -v jq >/dev/null 2>&1 || { echo "jq is required but not installed"; exit 1; }
	@command -v yq >/dev/null 2>&1 || { echo "yq is required but not installed"; exit 1; }
	@echo "Checking JSON formatting..."
	@for file in $(JSON_FILES); do \
		tmp="$$(mktemp)"; \
		jq . "$$file" > "$$tmp"; \
		if ! diff -u "$$file" "$$tmp"; then \
			rm -f "$$tmp"; \
			echo "$$file needs formatting (run 'make fmt')"; \
			exit 1; \
		fi; \
		rm -f "$$tmp"; \
	done
	@echo "Checking YAML parseability..."
	@for file in $(YAML_FILES); do \
		yq e '.' "$$file" >/dev/null; \
	done

lint: ## Lint all Helm charts
	@command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed"; exit 1; }
	@echo "Linting Helm charts..."
	@for chart in $(CHARTS); do \
		output="$$(mktemp)"; \
		helm lint "$$chart" > "$$output" 2>&1; \
		status="$$?"; \
		sed '/^\[INFO\] Chart.yaml: icon is recommended$$/d' "$$output"; \
		rm -f "$$output"; \
		if [ "$$status" -ne 0 ]; then \
			exit "$$status"; \
		fi; \
	done

validate: ## Render all Helm charts
	@command -v helm >/dev/null 2>&1 || { echo "helm is required but not installed"; exit 1; }
	@echo "Validating Helm chart renders..."
	@for chart in $(CHARTS); do \
		helm template "$$chart" >/dev/null; \
	done

precommit: ## Check formatting, lint charts, and validate renders
	@$(MAKE) check
	@$(MAKE) lint
	@$(MAKE) validate

update-manifests: ## Generate manifests/templates.json image metadata from chart values
	@echo "Updating manifests/templates.json from template chart values..."
	@go run scripts/manifests/main.go --output manifests/templates.json
