SCHEME        := Wardrobe
PROJECT       := Wardrobe.xcodeproj
DERIVED_DATA  := build/DerivedData
BUNDLE_ID     := com.example.wardrobe
SIM_ID        := $(shell scripts/simulator-id.sh)
DESTINATION   := platform=iOS Simulator,id=$(SIM_ID)
APP_PATH      := $(DERIVED_DATA)/Build/Products/Debug-iphonesimulator/Wardrobe.app

# Optional: make build DEVELOPMENT_TEAM=ABCDE12345
TEAM_FLAG := $(if $(DEVELOPMENT_TEAM),DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM),)

XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA) $(TEAM_FLAG)

.PHONY: help generate build test test-engine test-app test-ui run run-seed clean backend-install backend-dev backend-test

help:
	@echo "make generate     Generate Wardrobe.xcodeproj with XcodeGen"
	@echo "make build        Build the app for the iOS Simulator"
	@echo "make test         Run OutfitEngine, unit and UI tests"
	@echo "make run          Build, install and launch in the Simulator"
	@echo "make run-seed     Same, with the 25-garment sample closet (Debug only)"
	@echo "make backend-dev  Run the AI proxy locally on :8787"

generate:
	@command -v xcodegen >/dev/null || (echo "Install XcodeGen: brew install xcodegen" && exit 1)
	xcodegen generate

build: generate
	$(XCODEBUILD) build

test: test-engine test-app

test-engine:
	cd Packages/OutfitEngine && swift test

test-app: generate
	$(XCODEBUILD) test

test-ui: generate
	$(XCODEBUILD) test -only-testing:WardrobeUITests

run: build
	scripts/run-simulator.sh "$(SIM_ID)" "$(APP_PATH)" "$(BUNDLE_ID)"

run-seed: build
	scripts/run-simulator.sh "$(SIM_ID)" "$(APP_PATH)" "$(BUNDLE_ID)" -seed

clean:
	rm -rf build $(PROJECT)

backend-install:
	cd backend && npm install

backend-dev:
	cd backend && npm run dev

backend-test:
	cd backend && npm test
