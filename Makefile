# Dev commands. Run `make` for the list. Personal settings go in local.mk (see local.mk.example).
-include local.mk

PGDATA     ?= $(HOME)/.hacktx26/pgdata
PG         := $(shell brew --prefix 2>/dev/null)/opt/postgresql@17/bin
SIMULATOR  ?= iPhone 18 Pro
PORT       ?= 3000
# The phone reaches the server on your Mac's Wi-Fi address; set SERVER_URL in local.mk to use a tunnel instead.
LAN_IP     := $(shell ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null)
SERVER_URL ?= http://$(LAN_IP):$(PORT)

XCODE      := xcodebuild -project ios/Twin.xcodeproj -scheme Twin -configuration Debug -quiet
APP_DEVICE := build/ios-device/Build/Products/Debug-iphoneos/Twin.app
APP_SIM    := build/ios-sim/Build/Products/Debug-iphonesimulator/Twin.app
SIM_BUNDLE := com.sendtovishnu.hacktx26.twin

export LC_ALL := en_US.UTF-8

.PHONY: help setup server db-start db-stop db-reset test-ai sim phone phone-build devices ip tunnel

help: ## List commands
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/^([a-z-]+):.*## (.*)/\1|\2/' | awk -F'|' '{printf "  make %-12s %s\n", $$1, $$2}'

setup: ## One-time setup: tools, deps, server/.env, local Postgres, seed data
	@PGDATA="$(PGDATA)" ./scripts/dev-setup.sh

server: db-start ## Run the API server (restarts on file changes)
	cd server && npm run dev

db-start: ## Start local Postgres
	@$(PG)/pg_ctl -D "$(PGDATA)" status >/dev/null 2>&1 || $(PG)/pg_ctl -D "$(PGDATA)" -l "$(PGDATA)/log.txt" -w start >/dev/null

db-stop: ## Stop local Postgres
	$(PG)/pg_ctl -D "$(PGDATA)" stop

db-reset: db-start ## Wipe and re-seed the database (fresh demo state)
	cd server && npm run db:reset

test-ai: ## Run the AI and places checks against the live APIs
	cd server && npx tsx --env-file=.env scripts/try-ai.ts

sim: ## Build, install and launch on the iOS Simulator
	$(XCODE) -destination "platform=iOS Simulator,name=$(SIMULATOR)" -derivedDataPath build/ios-sim TWIN_SERVER_URL=http://localhost:$(PORT) build
	xcrun simctl boot "$(SIMULATOR)" 2>/dev/null || true
	@open "$$(xcode-select -p)/Applications/Simulator.app" 2>/dev/null || true
	xcrun simctl install "$(SIMULATOR)" $(APP_SIM)
	xcrun simctl launch --terminate-running-process "$(SIMULATOR)" $(SIM_BUNDLE)

phone-build: ## Build for a physical iPhone (needs TEAM_ID and BUNDLE_ID in local.mk)
	$(if $(TEAM_ID),,$(error Set TEAM_ID in local.mk: copy local.mk.example))
	$(if $(BUNDLE_ID),,$(error Set BUNDLE_ID in local.mk: copy local.mk.example))
	$(XCODE) -destination "generic/platform=iOS" -derivedDataPath build/ios-device \
	  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
	  DEVELOPMENT_TEAM=$(TEAM_ID) PRODUCT_BUNDLE_IDENTIFIER=$(BUNDLE_ID) CODE_SIGN_STYLE=Automatic \
	  TWIN_SERVER_URL=$(SERVER_URL) build

phone: phone-build ## Build, install and launch on your iPhone (DEVICE in local.mk)
	$(if $(DEVICE),,$(error Set DEVICE in local.mk: run `make devices` for names))
	xcrun devicectl device install app --device "$(DEVICE)" $(APP_DEVICE)
	xcrun devicectl device process launch --terminate-existing --device "$(DEVICE)" $(BUNDLE_ID)
	@echo "App points at $(SERVER_URL). Keep 'make server' running and the phone on the same Wi-Fi."

devices: ## List connected iPhones and simulators
	xcrun devicectl list devices

ip: ## Print the server URL the phone will use
	@echo $(SERVER_URL)

tunnel: ## Public https URL for the server (for a phone off your Wi-Fi)
	@command -v cloudflared >/dev/null || brew install cloudflared
	cloudflared tunnel --url http://localhost:$(PORT)
