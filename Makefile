.PHONY: run build clean release diagnose test integration-test setup-tests

# Build and run debug version
run:
	xcodebuild -project MeetingRecorder.xcodeproj -scheme MeetingRecorder -configuration Debug -derivedDataPath build build
	open build/Build/Products/Debug/MeetingRecorder.app

# Build debug version only
build:
	xcodebuild -project MeetingRecorder.xcodeproj -scheme MeetingRecorder -configuration Debug -derivedDataPath build build

# Build release version
release:
	./scripts/build-release.sh

# Diagnose recording issues
diagnose:
	./scripts/diagnose-recording.sh

# Test sample rate consistency (run after making a test recording)
# Usage: make test
#    or: make test RECORDING=path/to/file.m4a DURATION=10
test:
	./scripts/test-sample-rate.sh $(RECORDING) $(DURATION)

# Run integration tests (requires MeetingRecorderTests target in Xcode)
# Tests sample rate detection, recording duration, and guards against 2x speed bug
# First run 'make setup-tests' if you haven't added the test target yet
integration-test:
	xcodebuild test \
		-project MeetingRecorder.xcodeproj \
		-scheme MeetingRecorder \
		-destination 'platform=macOS' \
		-derivedDataPath build \
		2>&1 | xcbeautify || xcodebuild test \
		-project MeetingRecorder.xcodeproj \
		-scheme MeetingRecorder \
		-destination 'platform=macOS' \
		-derivedDataPath build

# Show instructions for setting up the test target in Xcode
setup-tests:
	./scripts/setup-test-target.sh

# Clean build artifacts
clean:
	rm -rf build release
