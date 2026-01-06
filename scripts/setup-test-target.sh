#!/bin/bash
# Setup script for MeetingRecorderTests target
# This script provides instructions for adding the test target to Xcode

set -e

echo "=== MeetingRecorder Test Target Setup ==="
echo ""
echo "The integration tests are located in: MeetingRecorderTests/"
echo ""
echo "To add the test target to your Xcode project:"
echo ""
echo "1. Open MeetingRecorder.xcodeproj in Xcode"
echo ""
echo "2. Go to File > New > Target..."
echo ""
echo "3. Select 'macOS' > 'Unit Testing Bundle'"
echo ""
echo "4. Configure the target:"
echo "   - Product Name: MeetingRecorderTests"
echo "   - Target to be Tested: MeetingRecorder"
echo "   - Language: Swift"
echo ""
echo "5. Click 'Finish'"
echo ""
echo "6. Add the existing test files to the new target:"
echo "   - Right-click MeetingRecorderTests folder in Xcode"
echo "   - Select 'Add Files to MeetingRecorder...'"
echo "   - Navigate to MeetingRecorderTests/"
echo "   - Select all .swift files"
echo "   - Ensure 'MeetingRecorderTests' target is checked"
echo ""
echo "7. Alternatively, drag these files into the MeetingRecorderTests group in Xcode:"
echo ""
find "$(dirname "$0")/../MeetingRecorderTests" -name "*.swift" -type f 2>/dev/null | while read file; do
    echo "   - $(basename "$file")"
done
echo ""
echo "8. Build and run tests with: make integration-test"
echo "   Or in Xcode: Product > Test (Cmd+U)"
echo ""
echo "=== Test Files ==="
echo ""
echo "Test files created:"
ls -la "$(dirname "$0")/../MeetingRecorderTests/" 2>/dev/null || echo "  (directory not found)"
echo ""
if [ -d "$(dirname "$0")/../MeetingRecorderTests/Helpers" ]; then
    echo "Helper files:"
    ls -la "$(dirname "$0")/../MeetingRecorderTests/Helpers/"
fi
