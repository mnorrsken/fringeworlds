# Regolith — convenience wrapper around the Godot CLI.
# Override the engine binary if it isn't on PATH:  make run GODOT=/path/to/godot

GODOT ?= godot
PROJECT := .

# Version string for the distributable archives, read from project.godot.
VERSION := $(shell sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
STAGE := build/stage

.DEFAULT_GOAL := help

.PHONY: help run editor build import test audio sprites playtest \
	export export-macos export-windows export-linux release clean

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

audio: ## Regenerate the synthesized sound assets (assets/audio/*.wav)
	python3 tools/gen_audio.py

sprites: ## Rebuild the sprite sheets from the authored GIFs (colonists, map objects)
	python3 tools/gif_to_sheet.py assets/characters assets/colonist.png
	python3 tools/gif_to_sheet.py --strip assets/objects/ice_asteroid_falling.gif \
		assets/objects/ice_asteroid_falling.png
	python3 tools/gif_to_sheet.py --strip assets/objects/ice_asteroid_crashing.gif \
		assets/objects/ice_asteroid_crashing.png

playtest: ## Headless pacing run: bot-plays several seeds and reports timings
	$(GODOT) --headless --script res://tools/playtest.gd

# --- distribution ------------------------------------------------------------
# Exports are unsigned: macOS is ad-hoc signed (required for Apple Silicon to
# run it at all, but not enough for Gatekeeper), Windows has no certificate.
# Each zip ships with the READ ME FIRST for that platform explaining the
# first-run warning. See DISTRIBUTING.md.

release: test export ## Run the tests, then build every distributable

export: export-macos export-windows export-linux ## Build distributable zips for all platforms
	@echo
	@ls -lh build/*.zip

export-macos: ## macOS universal (Intel + Apple Silicon) .app, zipped
	@rm -rf "$(STAGE)/Regolith-$(VERSION)-macos" && mkdir -p "$(STAGE)/Regolith-$(VERSION)-macos"
	$(GODOT) --headless --path $(PROJECT) --export-release "macOS" \
		"$(STAGE)/Regolith-$(VERSION)-macos/Regolith.app"
	@cp dist/READ-ME-FIRST-macos.txt "$(STAGE)/Regolith-$(VERSION)-macos/READ ME FIRST.txt"
	@# ditto, not zip: it preserves the bundle's symlinks and code signature.
	@cd $(STAGE) && ditto -c -k --sequesterRsrc --keepParent \
		"Regolith-$(VERSION)-macos" "../Regolith-$(VERSION)-macos.zip"

export-windows: ## Windows x86_64 .exe (pck embedded), zipped
	@rm -rf "$(STAGE)/Regolith-$(VERSION)-windows" && mkdir -p "$(STAGE)/Regolith-$(VERSION)-windows"
	$(GODOT) --headless --path $(PROJECT) --export-release "Windows" \
		"$(STAGE)/Regolith-$(VERSION)-windows/Regolith.exe"
	@cp dist/READ-ME-FIRST-windows.txt "$(STAGE)/Regolith-$(VERSION)-windows/READ ME FIRST.txt"
	@cd $(STAGE) && zip -qr "../Regolith-$(VERSION)-windows.zip" "Regolith-$(VERSION)-windows"

export-linux: ## Linux x86_64 binary (pck embedded), zipped
	@rm -rf "$(STAGE)/Regolith-$(VERSION)-linux" && mkdir -p "$(STAGE)/Regolith-$(VERSION)-linux"
	$(GODOT) --headless --path $(PROJECT) --export-release "Linux" \
		"$(STAGE)/Regolith-$(VERSION)-linux/Regolith.x86_64"
	@cp dist/READ-ME-FIRST-linux.txt "$(STAGE)/Regolith-$(VERSION)-linux/READ ME FIRST.txt"
	@cd $(STAGE) && zip -qr "../Regolith-$(VERSION)-linux.zip" "Regolith-$(VERSION)-linux"

clean: ## Remove Godot's generated cache and build output
	rm -rf $(PROJECT)/.godot $(PROJECT)/build
