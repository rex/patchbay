# ╔══════════════════════════════════════════════════════════════════════╗
# ║          patchbay — Makefile                                         ║
# ║          Swift 6 · SwiftPM · macOS 14.2+                             ║
# ╚══════════════════════════════════════════════════════════════════════╝
#
# Usage: make <target>
# Run `make help` for a full list of available targets.

.PHONY: help help-stack install env env-check setup update info dev \
        build install-command uninstall-command start lint typecheck fix \
        test version clean clean-all docker-build docker-run docker-stop \
        docker-clean db-generate db-push db-migrate db-studio db-reset

# ─── Configuration ────────────────────────────────────────────────────
APP_NAME    ?= patchbay
# Swift sources the formatter lints and fixes (only the ones that exist).
SWIFT_PATHS := $(wildcard Package.swift Sources Tests)
# Where `make install-command` puts the `patchbay` command.
PREFIX      ?= $(HOME)/.local
PORT        ?= 8000
NODE_ENV    ?= development
DOCKER_IMAGE := $(APP_NAME):latest

# ─── Skeleton core (skeleton-owned — never edit) ──────────────────────
# validate, the completion gate, check-*, bump-*, and sync-skeleton.
# Required: make stops if the file is missing, and
# `make check-skeleton` fails if it differs from the skeleton's copy.
# Add a gate with a prerequisite-only rule (`validate: check-foo`).
include make/agentic-skeleton.mk

# ─── Help ─────────────────────────────────────────────────────────────

## help: Display this help message with all available targets
help:
	@echo ""
	@echo "$(BOLD)$(CYAN)$(APP_NAME)$(RESET)"
	@echo "$(CYAN)════════════════════════════════════════════════════$(RESET)"
	@echo ""
	@echo "$(BOLD)Setup & Installation$(RESET)"
	@echo "  $(GREEN)make install$(RESET)              Install dependencies"
	@echo "  $(GREEN)make env$(RESET)                  Create .env from template"
	@echo "  $(GREEN)make env-check$(RESET)            Verify required env vars"
	@echo "  $(GREEN)make setup$(RESET)                Full setup: install + typecheck"
	@echo ""
	@echo "$(BOLD)Development$(RESET)"
	@echo "  $(GREEN)make dev$(RESET)                  Run patchbay from source"
	@echo "  $(GREEN)make build$(RESET)                Build the release binary"
	@echo "  $(GREEN)make install-command$(RESET)      Install \`patchbay\` to $(PREFIX)/bin (rerun after pulling)"
	@echo "  $(GREEN)make uninstall-command$(RESET)    Remove it again"
	@echo "  $(GREEN)make start$(RESET)                Start production server"
	@echo "  $(GREEN)make lint$(RESET)                 Run linter"
	@echo "  $(GREEN)make typecheck$(RESET)            Run type checker"
	@echo "  $(GREEN)make check-architecture$(RESET)   Run repo-native architecture checks"
	@echo "  $(GREEN)make fix$(RESET)                  Auto-fix lint issues"
	@echo "  $(GREEN)make test$(RESET)                 Run tests (when testing is enabled)"
	@echo "  $(GREEN)make validate$(RESET)             Run aggregate validation: lint + typecheck + architecture + version-gate"
	@echo "  $(GREEN)make check-skills$(RESET)         Advisory: applied-skill provenance + drift (never fails)"
	@echo "  $(GREEN)make stamp-skill$(RESET)          Record an applied skill: SKILL=<id> [VERSION=x.y.z]"
	@echo ""
	@echo "$(BOLD)Versioning (required before every commit)$(RESET)"
	@echo "  $(GREEN)make version$(RESET)              Print current VERSION"
	@echo "  $(GREEN)make bump-patch$(RESET)           Bump patch (x.y.Z+1) — bug fixes / doc / refactor"
	@echo "  $(GREEN)make bump-minor$(RESET)           Bump minor (x.Y+1.0) — additive feature, backward-compat"
	@echo "  $(GREEN)make bump-major$(RESET)           Bump major (X+1.0.0) — breaking change"
	@echo ""
	@echo "$(BOLD)Docker$(RESET)"
	@echo "  $(GREEN)make docker-build$(RESET)         Build Docker image"
	@echo "  $(GREEN)make docker-run$(RESET)           Run container (port $(PORT))"
	@echo "  $(GREEN)make docker-stop$(RESET)          Stop container"
	@echo "  $(GREEN)make docker-clean$(RESET)         Remove image and container"
	@echo ""
	@echo "$(BOLD)Maintenance$(RESET)"
	@echo "  $(GREEN)make clean$(RESET)                Remove build cache"
	@echo "  $(GREEN)make clean-all$(RESET)            Remove build cache + deps (destructive!)"
	@echo "  $(GREEN)make update$(RESET)               Update dependencies"
	@echo "  $(GREEN)make info$(RESET)                 Show project info"
	@echo ""
	@echo "$(BOLD)Completion$(RESET)"
	@echo "  $(GREEN)make check-if-the-agent-can-consider-this-task-completed$(RESET)"
	@echo "    Final verification gate (required before declaring a task complete)"
	@echo ""
	@echo "$(BOLD)Variables$(RESET)"
	@echo "  PORT=$(PORT)  (override: make dev PORT=3000)"
	@echo ""

# ─── Setup & Installation ────────────────────────────────────────────

## install: Resolve SwiftPM dependencies
install:
	@echo "$(CYAN)Resolving Swift packages...$(RESET)"
	@swift package resolve
	@echo "$(GREEN)Done.$(RESET)"

## env: Create .env from template if missing
env:
	@if [ ! -f .env ]; then \
		if [ -f .env.example ]; then \
			echo "$(YELLOW)Creating .env from .env.example...$(RESET)"; \
			cp .env.example .env; \
			echo "$(GREEN).env created. Configure before running.$(RESET)"; \
		else \
			echo "$(RED)No .env.example to copy from.$(RESET)"; exit 1; \
		fi \
	else \
		echo "$(YELLOW).env already exists, skipping.$(RESET)"; \
	fi

## env-check: Verify required env vars are set
env-check:
	@if [ ! -f .env ]; then echo "$(RED).env missing — run 'make env'.$(RESET)"; exit 1; fi
	@echo "$(GREEN).env present.$(RESET)"

## setup: Full project setup (patchbay needs no .env)
setup: install typecheck
	@echo ""
	@echo "$(GREEN)$(BOLD)Setup complete!$(RESET)"
	@echo "  Run $(CYAN)make dev$(RESET) to start developing."

# ─── Versioning (non-negotiable: every commit gets a bump) ───────────

## version: Print current VERSION
version:
	@cat VERSION 2>/dev/null || echo "0.1.0 (VERSION file missing)"

# ─── Development ──────────────────────────────────────────────────────

## dev: Run patchbay from source
dev:
	@swift run patchbay

## build: Build the release binary (.build/release/patchbay)
build:
	@echo "$(CYAN)Building release binary...$(RESET)"
	@swift build -c release

## install-command: Build and install the `patchbay` command to $(PREFIX)/bin
install-command: build
	@mkdir -p "$(PREFIX)/bin"
	@install -m 755 .build/release/patchbay "$(PREFIX)/bin/patchbay"
	@echo "$(GREEN)Installed $(PREFIX)/bin/patchbay$(RESET)"
	@case ":$$PATH:" in *":$(PREFIX)/bin:"*) ;; \
		*) echo "$(YELLOW)  $(PREFIX)/bin is not on your PATH; add it to run \`patchbay\` anywhere.$(RESET)" ;; \
	esac

## uninstall-command: Remove the installed `patchbay` command
uninstall-command:
	@rm -f "$(PREFIX)/bin/patchbay"
	@echo "$(GREEN)Removed $(PREFIX)/bin/patchbay$(RESET)"

## start: Start production server
start:
	@echo "$(CYAN)Starting production server on port $(PORT)...$(RESET)"
	@echo "$(YELLOW)  (stub — overlay a lang-* skill to fill this in; run 'make help-stack')$(RESET)"

## lint: swift-format in strict lint mode (warnings fail)
lint:
	@echo "$(CYAN)Running swift-format lint...$(RESET)"
	@swift format lint --strict --recursive $(SWIFT_PATHS)

## typecheck: Compile every target (Swift 6 language mode, strict concurrency)
typecheck:
	@echo "$(CYAN)Compiling (type check)...$(RESET)"
	@swift build --build-tests

## fix: Reformat Swift sources in place with swift-format
fix:
	@echo "$(CYAN)Formatting Swift sources...$(RESET)"
	@swift format format --in-place --recursive $(SWIFT_PATHS)

## test: Run tests — VIBE.yaml quality_gates.tests.mode decides (fails closed when required)
test:
	@echo "$(CYAN)Running tests...$(RESET)"
	@MODE=$$(python3 -c "import yaml;d=yaml.safe_load(open('VIBE.yaml'));print((((d or {}).get('quality_gates') or {}).get('tests') or {}).get('mode') or 'deferred')" 2>/dev/null) \
		|| MODE=$$(uv run --with pyyaml python3 -c "import yaml;d=yaml.safe_load(open('VIBE.yaml'));print((((d or {}).get('quality_gates') or {}).get('tests') or {}).get('mode') or 'deferred')" 2>/dev/null) \
		|| MODE=unknown; \
	case "$$MODE" in \
		required) \
			swift test ;; \
		deferred|not_applicable) \
			echo "$(YELLOW)  tests.mode='$$MODE' — tests not run, NOT claimed as passing.$(RESET)" ;; \
		*) \
			echo "$(RED)  Could not read quality_gates.tests.mode from VIBE.yaml —$(RESET)"; \
			echo "$(RED)  failing closed.$(RESET)"; \
			exit 1 ;; \
	esac

# ─── Docker ───────────────────────────────────────────────────────────

## docker-build: Build Docker image with version metadata
docker-build:
	@echo "$(CYAN)Building Docker image $(DOCKER_IMAGE)...$(RESET)"
	docker build \
		--build-arg APP_VERSION=$$(git describe --tags --always 2>/dev/null || echo "dev") \
		--build-arg GITHUB_SHA=$$(git rev-parse HEAD 2>/dev/null || echo "unknown") \
		--build-arg BUILD_DATE=$$(date -u +%Y-%m-%dT%H:%M:%SZ) \
		-t $(DOCKER_IMAGE) .

## docker-run: Run container on port $(PORT)
docker-run:
	@docker run -d --rm --name $(APP_NAME) -p $(PORT):$(PORT) --env-file .env $(DOCKER_IMAGE)
	@echo "$(GREEN)Container running on port $(PORT).$(RESET)"

## docker-stop: Stop container
docker-stop:
	@docker stop $(APP_NAME) 2>/dev/null || true
	@echo "$(GREEN)Container stopped.$(RESET)"

## docker-clean: Remove image and container
docker-clean: docker-stop
	@docker rmi -f $(DOCKER_IMAGE) 2>/dev/null || true
	@echo "$(GREEN)Image removed.$(RESET)"

# ─── Maintenance ──────────────────────────────────────────────────────

## clean: Remove build cache
clean:
	@echo "$(CYAN)Cleaning build cache...$(RESET)"
	@rm -rf build/ dist/ .next/ .turbo/ __pycache__/ .pytest_cache/ .mypy_cache/ .ruff_cache/
	@echo "$(GREEN)Clean.$(RESET)"

## clean-all: Remove build cache + dependencies (destructive — requires confirmation)
clean-all:
	@echo "$(YELLOW)WARNING: This will remove all dependencies and build artifacts.$(RESET)"
	@read -p "Are you sure? [y/N] " confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		rm -rf build/ dist/ .next/ .turbo/ __pycache__/ .pytest_cache/ \
			.mypy_cache/ .ruff_cache/ node_modules/ .venv/ uv.lock; \
		echo "$(GREEN)Deep clean complete.$(RESET)"; \
	else \
		echo "$(YELLOW)Cancelled.$(RESET)"; \
	fi

## update: Update dependencies (stack-specific)
update:
	@echo "$(CYAN)Updating dependencies...$(RESET)"
	@echo "$(YELLOW)  (stub — overlay a lang-* skill to fill this in; run 'make help-stack')$(RESET)"

## info: Show project state
info:
	@echo "$(BOLD)$(CYAN)Project Info$(RESET)"
	@echo "──────────────────────────────"
	@echo "  Project: $(APP_NAME)"
	@echo "  Branch:  $$(git branch --show-current 2>/dev/null || echo 'N/A')"
	@echo "  Commit:  $$(git rev-parse --short HEAD 2>/dev/null || echo 'N/A')"
	@echo "  Tree:    $$(git status --porcelain | wc -l | tr -d ' ') uncommitted changes"
	@echo "  Port:    $(PORT)"

# ─── Required-files + commit-surface gates ──────────────────────────

# ─── Completion Gate ──────────────────────────────────────────────────

## help-stack: Show which lang-* skill should fill in stub targets
help-stack:
	@echo "$(BOLD)$(CYAN)Stub targets and their owning lang-* skills$(RESET)"
	@echo ""
	@echo "Greenfield Makefile targets that print '(stub — overlay a lang-* skill"
	@echo "to fill this in)' need a stack-specific skill to overlay recipe bodies."
	@echo "Pick the skill matching VIBE.yaml::project.stack:"
	@echo ""
	@echo "  $(GREEN)Python / FastAPI$(RESET)        → invoke $(BOLD)/lang-python$(RESET)"
	@echo "  $(GREEN)Next.js / App Router$(RESET)    → invoke $(BOLD)/lang-react$(RESET)"
	@echo "  $(GREEN)Vite SPA$(RESET)                → invoke $(BOLD)/lang-react-spa$(RESET) + $(BOLD)/tool-vite$(RESET)"
	@echo "  $(GREEN)Go$(RESET)                      → invoke $(BOLD)/lang-go$(RESET) (when shipped)"
	@echo "  $(GREEN)MCP server$(RESET)              → invoke $(BOLD)/lang-mcp$(RESET) (when shipped)"
	@echo ""
	@echo "Each lang-* skill provides recipe bodies for: install / dev / build /"
	@echo "start / lint / typecheck / fix / test / update."
	@echo ""
	@echo "Until a lang-* overlay is applied, the stubs do nothing — that is by"
	@echo "design (the skeleton stays stack-agnostic). See"
	@echo "agentic-skeleton/SKILL.md for skill composition guidance."
	@echo ""

.DEFAULT_GOAL := help
