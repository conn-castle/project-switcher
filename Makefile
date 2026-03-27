.PHONY: help setup build build-dev test test-app test-core test-cli test-one coverage clean regen hooks preflight test-coverage-gate

help:
	@echo "ProjectSwitcher development commands:"
	@echo ""
	@echo "  make setup               Validate Xcode toolchain (run once after clone)"
	@echo "  make build               Build app + CLI (Debug, no code signing)"
	@echo "  make build-dev           Build dev app identity (Debug, no code signing)"
	@echo "  make test                Run all tests with coverage collection"
	@echo "  make test-app            Run ProjectSwitcherAppTests only"
	@echo "  make test-core           Run ProjectSwitcherCoreTests only"
	@echo "  make test-cli            Run ProjectSwitcherCLITests only"
	@echo "  make test-one            Run a single test (TARGET=... TEST=...)"
	@echo "  make coverage            Run tests with coverage gate enforcement"
	@echo "  make clean               Remove build artifacts"
	@echo "  make regen               Regenerate Xcode project from project.yml"
	@echo "  make hooks               Install git pre-commit hook"
	@echo "  make preflight           Validate release configuration"
	@echo "  make test-coverage-gate  Run coverage_gate.swift integration tests"

setup:
	scripts/dev_bootstrap.sh

build:
	scripts/build.sh

build-dev:
	scripts/build_dev.sh

test:
	scripts/test.sh

test-app:
	scripts/test.sh --target ProjectSwitcherAppTests

test-core:
	scripts/test.sh --target ProjectSwitcherCoreTests

test-cli:
	scripts/test.sh --target ProjectSwitcherCLITests

test-one:
	@if [ -z "$(TARGET)" ] || [ -z "$(TEST)" ]; then \
		echo "error: make test-one requires TARGET and TEST"; \
		echo "usage: make test-one TARGET=<BundleName> TEST=<ClassName/testMethod>"; \
		exit 2; \
	fi
	scripts/test.sh --target "$(TARGET)" --test "$(TEST)"

coverage:
	scripts/test.sh --gate

clean:
	scripts/clean.sh

regen:
	scripts/regenerate_xcodeproj.sh

hooks:
	scripts/install_git_hooks.sh

preflight:
	scripts/ci_preflight.sh

test-coverage-gate:
	scripts/test_coverage_gate.sh
