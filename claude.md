# MeetingRecorder - macOS System Audio and Microphone simultaneous recording App

**Design Document**: [Technical Requirements](../technical-requirements.md)

## Technical Requirements
- **Language**: Swift 6
- **Audio Layer**: Core Audio and the modern system-audio capture APIs


**Official Documentation**: [Capturing System Audio with Core Audio Taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)

### Key Features:
- System audio capture via process taps
- Simultaneous recording of system audio and microphone input

---

## Known Issues & Solutions

### Audio Playback Speed (2x Speed Bug)

**Problem**: Recorded audio plays back at 2x speed (or other incorrect speeds).

**Root Cause**: Sample rate mismatch between the audio tap format and the actual device operating rate.

- The audio tap (`kAudioTapPropertyFormat`) reports the source audio's sample rate (e.g., 48kHz from YouTube)
- But the aggregate device operates at the **system output device's rate** (which may differ, e.g., 24kHz for AirPods)
- When audio data arrives at rate X but is written to a file labeled as rate Y, playback speed = Y/X

**Solution**: Always use the **system output device's actual sample rate** for recording, not the tap format rate.

Priority order for determining sample rate (in `ProcessTap.swift`):
1. System output device ACTUAL rate (`kAudioDevicePropertyActualSampleRate`)
2. Aggregate device ACTUAL rate
3. Aggregate device NOMINAL rate
4. System output device NOMINAL rate
5. Tap format rate (fallback only)

**Diagnostic Logging**: Check Console.app with filter `subsystem == "com.zamai.MeetingRecorder"`
- `=== SAMPLE RATE DIAGNOSTIC ===` - at recording start
- `=== RECORDING DIAGNOSTIC ===` - at recording end with speed ratio

---

## Testing

### Quick Tests (Shell-based)
```bash
make test                                    # Auto-detect recent recording
make test RECORDING=file.m4a DURATION=10     # Test specific file
make diagnose                                # Analyze recent recordings
```

### Integration Tests (XCTest)

The integration tests guard against the 2x speed bug by verifying:
- Recording duration matches wall clock time
- Sample rate detection is consistent
- Frequency content is preserved

**Setup** (one-time):
```bash
make setup-tests    # Shows instructions for adding test target to Xcode
```

**Run tests**:
```bash
make integration-test
```

**Test files**:
- `MeetingRecorderTests/AudioIntegrationTests.swift` - Main test suite
- `MeetingRecorderTests/SampleRateTests.swift` - Sample rate detection tests
- `MeetingRecorderTests/Helpers/SineWaveGenerator.swift` - Test audio generation
- `MeetingRecorderTests/Helpers/AudioAnalyzer.swift` - FFT analysis for verification

---

## Development Workflow Rules

### Compilation Warnings Check
**MANDATORY**: Always check for compilation warnings as the final step before completing any task.

#### How to Check for Compilation Warnings:
```bash
xcodebuild -project MeetingRecorder.xcodeproj -scheme MeetingRecorder -configuration Debug clean build 2>&1 | grep -E "warning:|error:|note:"
```

#### Rules:
1. Run the warnings check after making any code changes
2. Address all warnings before marking a task as complete
3. If warnings exist, fix them or discuss with the user before proceeding
4. Include the warning check results in your completion summary
