.PHONY: run build clean release diagnose test

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

# Clean build artifacts
clean:
	rm -rf build release
