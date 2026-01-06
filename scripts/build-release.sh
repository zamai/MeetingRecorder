#!/bin/bash
set -e

VERSION="${1:-1.0.0}"
BUILD_DIR="build"
RELEASE_DIR="release"

echo "Building MeetingRecorder v$VERSION..."

# Clean
rm -rf "$BUILD_DIR" "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Build
xcodebuild -project MeetingRecorder.xcodeproj \
  -scheme MeetingRecorder \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  | grep -E "^(Build|Compile|Link|error:|warning:)" || true

# Check if app was built
APP_PATH="$BUILD_DIR/Build/Products/Release/MeetingRecorder.app"
if [ ! -d "$APP_PATH" ]; then
  echo "Error: Build failed - MeetingRecorder.app not found"
  exit 1
fi

# Package
echo "Packaging..."
cd "$BUILD_DIR/Build/Products/Release"
zip -r -q "../../../../$RELEASE_DIR/MeetingRecorder-$VERSION.zip" MeetingRecorder.app
cd ../../../../

# Generate SHA256
SHA256=$(shasum -a 256 "$RELEASE_DIR/MeetingRecorder-$VERSION.zip" | cut -d' ' -f1)

echo ""
echo "========================================"
echo "  Release Ready!"
echo "========================================"
echo ""
echo "File: $RELEASE_DIR/MeetingRecorder-$VERSION.zip"
echo "SHA256: $SHA256"
echo ""
echo "Next steps:"
echo "1. Create GitHub release: https://github.com/zamai/MeetingRecorder/releases/new"
echo "2. Tag: v$VERSION"
echo "3. Upload: $RELEASE_DIR/MeetingRecorder-$VERSION.zip"
echo ""
echo "Update Cask formula (homebrew-tap/Casks/meetingrecorder.rb):"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA256\""
