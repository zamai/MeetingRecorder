# MeetingRecorder

A simple macOS menu bar app that does one thing: records your microphone and system audio simultaneously into a single M4A file.

## Features

- Records system audio and microphone input at the same time
- Lives in the menu bar for quick access
- Outputs to M4A (AAC) format
- Automatically merges audio tracks into a single file

## Requirements

- macOS 14.0 (Sonoma) or later
- Microphone permission
- Screen recording permission (for system audio capture)

## Installation

```bash
brew install --cask zamai/tap/meetingrecorder
```

Or download manually from the [Releases](https://github.com/zamai/MeetingRecorder/releases) page.

## Development

```bash
make run      # Build and run debug version
make build    # Build debug version only
make release  # Build release version
make clean    # Clean build artifacts
```

## Analytics

This app sends a single anonymous event to [PostHog](https://posthog.com) when you first launch it. That's it. I'm just curious if anyone will ever install this thing :)

See exactly what's tracked: [PostHogAnalytics.swift](MeetingRecorder/PostHogAnalytics.swift)

## License

This project is free and open source, available under the [Apache 2.0 License](LICENSE).

## Contributing

This app was created by a backend engineer using LLMs. Contributions are welcome, especially from developers with experience in native macOS development. If you can help make this app more Apple-native and macOS-like, please open a PR!
