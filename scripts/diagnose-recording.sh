#!/bin/bash
# Diagnostic script for MeetingRecorder audio sample rate issues
# Usage: ./scripts/diagnose-recording.sh [recording_file]

set -e

echo "=== MeetingRecorder Audio Diagnostic ==="
echo ""

# If a file is provided, analyze it
if [ -n "$1" ]; then
    if [ -f "$1" ]; then
        echo "Analyzing: $1"
        echo ""
        afinfo "$1"
        exit 0
    else
        echo "Error: File not found: $1"
        exit 1
    fi
fi

# Otherwise, find recent recordings
echo "Looking for recent recordings..."
echo ""

# Check Desktop
DESKTOP_FILES=$(find ~/Desktop -name "*.m4a" -mmin -60 2>/dev/null | head -5)

# Check App Support
APP_SUPPORT_FILES=$(find ~/Library/Application\ Support/MeetingRecorder -name "*.m4a" -mmin -60 2>/dev/null | head -5)

ALL_FILES="$DESKTOP_FILES $APP_SUPPORT_FILES"

if [ -z "$ALL_FILES" ]; then
    echo "No recent recordings found (last 60 minutes)"
    echo ""
    echo "To test:"
    echo "1. Run: make run"
    echo "2. Record for exactly 10 seconds (count aloud: 1, 2, 3... 10)"
    echo "3. Stop recording"
    echo "4. Run this script again"
    exit 1
fi

echo "Found recordings:"
echo ""

for file in $ALL_FILES; do
    if [ -f "$file" ]; then
        echo "============================================"
        echo "File: $(basename "$file")"
        echo "Path: $file"
        echo "--------------------------------------------"
        afinfo "$file" 2>/dev/null | grep -E "(Data format|estimated duration|bit rate)"
        echo ""
    fi
done

echo "============================================"
echo ""
echo "DIAGNOSIS:"
echo "- If you recorded for 10 seconds but duration shows ~5 seconds: 2x speed bug"
echo "- If you recorded for 10 seconds but duration shows ~20 seconds: 0.5x speed bug"
echo "- If duration matches recording time: sample rate is correct"
echo ""
echo "Check Console.app for detailed sample rate logs from MeetingRecorder"
