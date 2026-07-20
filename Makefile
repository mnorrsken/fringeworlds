# Regolith — convenience wrapper around the Godot CLI.
# Override the engine binary if it isn't on PATH:  make run GODOT=/path/to/godot

GODOT ?= godot
PROJECT := .

.DEFAULT_GOAL := help

.PHONY: help run editor build import test clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

run: ## Run the game (main scene)
	$(GODOT) --path $(PROJECT)

editor: ## Open the project in the Godot editor
	$(GODOT) --editor --path $(PROJECT)

build: import ## Alias for `import`: compile + reimport, fail on errors

import: ## Headless import: build the .godot cache and catch script/asset errors
	$(GODOT) --headless --editor --quit --path $(PROJECT)

test: ## Run headless sim tests (non-zero exit on failure)
	$(GODOT) --headless --path $(PROJECT) --script res://tests/run_tests.gd

clean: ## Remove Godot's generated cache
	rm -rf $(PROJECT)/.godot
