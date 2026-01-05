# AudioCap - macOS System Audio and Microphone simultaneous recording App

**Design Document**: [Technical Requirements](../technical-requirements.md)

## Technical Requirements
- **Language**: Swift 6
- **Audio Layer**: Core Audio and the modern system-audio capture APIs


**Official Documentation**: [Capturing System Audio with Core Audio Taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps)

### Key Features:
- System audio capture via process taps
- Simultaneous recording of system audio and microphone input

## Development Workflow Rules

### Compilation Warnings Check
**MANDATORY**: Always check for compilation warnings as the final step before completing any task.

#### How to Check for Compilation Warnings:
```bash
xcodebuild -project AudioCap.xcodeproj -scheme AudioCap -configuration Debug clean build 2>&1 | grep -E "warning:|error:|note:"
```

#### Rules:
1. Run the warnings check after making any code changes
2. Address all warnings before marking a task as complete
3. If warnings exist, fix them or discuss with the user before proceeding
4. Include the warning check results in your completion summary
