#!/bin/bash
# Integration test for sample rate consistency
# This test verifies that recordings don't have the 2x speed bug
#
# Usage: ./scripts/test-sample-rate.sh [recording_file] [expected_duration_seconds]
#
# The test passes if:
# 1. The file's duration matches expected duration within 10% tolerance
# 2. The sample rate in the file is a standard rate (24000, 44100, 48000, 96000)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== MeetingRecorder Sample Rate Integration Test ==="
echo ""

# Check if afinfo is available
if ! command -v afinfo &> /dev/null; then
    echo -e "${RED}ERROR: afinfo command not found. This test requires macOS.${NC}"
    exit 1
fi

# If a file is provided, analyze it
if [ -n "$1" ]; then
    RECORDING_FILE="$1"
    EXPECTED_DURATION="${2:-0}"
else
    # Find the most recent recording
    echo "Looking for most recent recording..."

    # Check common recording locations
    RECORDING_FILE=$(find ~/Desktop ~/Library/Application\ Support/MeetingRecorder -name "*.m4a" -mmin -30 2>/dev/null | head -1)

    if [ -z "$RECORDING_FILE" ]; then
        echo -e "${YELLOW}No recent recordings found (last 30 minutes).${NC}"
        echo ""
        echo "To run this test:"
        echo "1. Start the MeetingRecorder app"
        echo "2. Start a recording and count aloud: '1, 2, 3... 10'"
        echo "3. Stop the recording after exactly 10 seconds"
        echo "4. Run: ./scripts/test-sample-rate.sh <recording_file> 10"
        echo ""
        echo "Or run without arguments after making a recording to auto-detect."
        exit 1
    fi

    echo "Found: $RECORDING_FILE"
    echo ""
fi

# Verify file exists
if [ ! -f "$RECORDING_FILE" ]; then
    echo -e "${RED}ERROR: File not found: $RECORDING_FILE${NC}"
    exit 1
fi

echo "Analyzing: $(basename "$RECORDING_FILE")"
echo "Path: $RECORDING_FILE"
echo ""

# Get file info using afinfo
AFINFO_OUTPUT=$(afinfo "$RECORDING_FILE" 2>&1)

# Extract key values
FILE_SAMPLE_RATE=$(echo "$AFINFO_OUTPUT" | grep "sample rate:" | head -1 | awk '{print $NF}')
FILE_DURATION=$(echo "$AFINFO_OUTPUT" | grep "estimated duration:" | awk '{print $3}')
FILE_CHANNELS=$(echo "$AFINFO_OUTPUT" | grep "channel(s)" | awk '{print $1}')

echo "File Analysis:"
echo "  Sample Rate: ${FILE_SAMPLE_RATE} Hz"
echo "  Duration: ${FILE_DURATION} seconds"
echo "  Channels: ${FILE_CHANNELS}"
echo ""

# Test 1: Verify sample rate is a standard rate
VALID_RATES="24000 44100 48000 96000"
RATE_VALID=false
for rate in $VALID_RATES; do
    if [ "$FILE_SAMPLE_RATE" = "$rate" ]; then
        RATE_VALID=true
        break
    fi
done

if [ "$RATE_VALID" = true ]; then
    echo -e "${GREEN}[PASS]${NC} Sample rate ($FILE_SAMPLE_RATE Hz) is a valid standard rate"
else
    echo -e "${YELLOW}[WARN]${NC} Sample rate ($FILE_SAMPLE_RATE Hz) is non-standard (expected: $VALID_RATES)"
fi

# Test 2: If expected duration provided, verify it matches
if [ "$EXPECTED_DURATION" != "0" ] && [ -n "$EXPECTED_DURATION" ]; then
    # Calculate tolerance (10%)
    TOLERANCE=$(echo "$EXPECTED_DURATION * 0.1" | bc -l)
    LOWER_BOUND=$(echo "$EXPECTED_DURATION - $TOLERANCE" | bc -l)
    UPPER_BOUND=$(echo "$EXPECTED_DURATION + $TOLERANCE" | bc -l)

    # Compare durations
    DURATION_MATCH=$(echo "$FILE_DURATION >= $LOWER_BOUND && $FILE_DURATION <= $UPPER_BOUND" | bc -l)

    if [ "$DURATION_MATCH" = "1" ]; then
        echo -e "${GREEN}[PASS]${NC} Duration ($FILE_DURATION s) matches expected ($EXPECTED_DURATION s) within 10% tolerance"
    else
        SPEED_RATIO=$(echo "scale=2; $EXPECTED_DURATION / $FILE_DURATION" | bc -l)
        echo -e "${RED}[FAIL]${NC} Duration mismatch! File: ${FILE_DURATION}s, Expected: ${EXPECTED_DURATION}s"
        echo -e "${RED}       Speed ratio: ${SPEED_RATIO}x (1.0 = correct, 2.0 = 2x speed bug)${NC}"

        # Provide diagnosis
        if (( $(echo "$SPEED_RATIO > 1.8 && $SPEED_RATIO < 2.2" | bc -l) )); then
            echo ""
            echo -e "${RED}DIAGNOSIS: 2x speed bug detected!${NC}"
            echo "The sample rate used for recording doesn't match the actual audio data rate."
            echo "Check the system output device sample rate vs tap format rate."
        elif (( $(echo "$SPEED_RATIO > 0.45 && $SPEED_RATIO < 0.55" | bc -l) )); then
            echo ""
            echo -e "${RED}DIAGNOSIS: 0.5x speed bug detected (audio plays too slow)!${NC}"
        fi

        exit 1
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} Duration test skipped (no expected duration provided)"
    echo "       To test duration: ./scripts/test-sample-rate.sh \"$RECORDING_FILE\" <expected_seconds>"
fi

# Test 3: Check Console logs for sample rate diagnostics
echo ""
echo "Checking recent diagnostic logs..."

LOG_OUTPUT=$(/usr/bin/log show --predicate 'subsystem == "com.zamai.MeetingRecorder"' --last 30m --style compact 2>&1 | grep -E "(Speed ratio|CRITICAL|BUG)" || true)

if [ -n "$LOG_OUTPUT" ]; then
    if echo "$LOG_OUTPUT" | grep -q "BUG\|CRITICAL"; then
        echo -e "${RED}[FAIL]${NC} Sample rate issues detected in logs:"
        echo "$LOG_OUTPUT" | head -5
        exit 1
    else
        # Check speed ratio from logs
        SPEED_RATIO_LOG=$(echo "$LOG_OUTPUT" | grep "Speed ratio" | tail -1 | grep -oE "[0-9]+\.[0-9]+" || echo "")
        if [ -n "$SPEED_RATIO_LOG" ]; then
            RATIO_OK=$(echo "$SPEED_RATIO_LOG > 0.9 && $SPEED_RATIO_LOG < 1.1" | bc -l)
            if [ "$RATIO_OK" = "1" ]; then
                echo -e "${GREEN}[PASS]${NC} Speed ratio from logs: ${SPEED_RATIO_LOG}x (expected ~1.0)"
            else
                echo -e "${RED}[FAIL]${NC} Speed ratio from logs: ${SPEED_RATIO_LOG}x (expected ~1.0)"
                exit 1
            fi
        fi
    fi
else
    echo -e "${YELLOW}[SKIP]${NC} No diagnostic logs found (recording may be older than 30 minutes)"
fi

echo ""
echo "=== Test Summary ==="
echo -e "${GREEN}All checks passed!${NC}"
echo ""
