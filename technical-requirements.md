# MeetingRecorder Technical Requirements

MeetingRecorder is a macOS status-bar application that records system audio + default microphone into a single M4A file using modern Core Audio capture APIs. One click starts/stops recording. Files are saved to Desktop by default and flushed to disk every second to allow partial-recording recovery.

⸻

## Key Features (Functional)
- Status-bar app with one-click Start/Stop.
- Capture system audio and default microphone, mixed into one stream.
- Output format: M4A (AAC).
- Save location: Desktop (configurable).
- Crash-tolerant: flush encoded audio to disk every 1 second.
- File naming: MeetingRecorder_<YYYY-MM-DD>T<hh-mm-ss>.m4a using local time.
- Request system-audio and microphone permissions on first use.

⸻

## Permissions & Privacy
- Request microphone access via NSMicrophoneUsageDescription.
- Request system-audio capture authorization through the latest macOS system-audio capture APIs.
- If permissions are denied, block recording start and guide users to System Settings.
- No network usage; all audio remains local.

⸻

## UI / UX
- Status-bar (NSStatusItem) interface.
- Menu: Start/Stop, Quit.
- Recording indicator.

⸻

## Technical Requirements
- Language: Swift (latest stable version).
- Audio layer: Core Audio and the modern system-audio capture APIs.
