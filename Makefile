SHELL := /bin/bash
PROJECT := XcodeProject/sshido.xcodeproj
SCHEME  := sshido
CONFIG  := Debug

.PHONY: bootstrap generate build run run-sim test clean doctor archive bump beta

bootstrap:
	@bash scripts/bootstrap.sh

generate:
	@command -v xcodegen >/dev/null || { echo "install xcodegen: brew install xcodegen"; exit 1; }
	@cd XcodeProject && xcodegen generate

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	  -destination 'generic/platform=iOS' build

run: generate
	@bash scripts/run-device.sh

run-sim: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
	  -destination 'platform=iOS Simulator,name=iPhone 15' build
	@bash scripts/run-sim.sh

test:
	swift test
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
	  -destination 'platform=iOS Simulator,name=iPhone 15' test || true

clean:
	rm -rf build .build DerivedData XcodeProject/sshido.xcodeproj

doctor:
	@bash scripts/doctor.sh

archive:
	@bash scripts/archive.sh

bump:
	@bash scripts/bump-build.sh

beta:
	@fastlane beta
