import SwiftUI

@MainActor
struct RootView: View {
    @State private var settingsWindow: NSWindow?
    @State private var recordingState = RecordingState.shared

    var body: some View {
        VStack(spacing: 12) {
            // When recording, show prominent Stop button at top
            if recordingState.isRecording {
                Button(action: {
                    recordingState.stopAction?()
                }) {
                    HStack {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(.red)
                        Text("Stop Recording")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)

                Divider()
            }

            SystemAudioRecordingView()

            Divider()

            HStack {
                Button("Settings") {
                    if settingsWindow == nil {
                        let settingsView = SettingsView()
                        settingsWindow = NSWindow(contentViewController: NSHostingController(rootView: settingsView))
                        settingsWindow?.title = "Settings"
                    }
                    settingsWindow?.makeKeyAndOrderFront(nil)
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding()
    }
}

struct SettingsView: View {
    @AppStorage("shouldMergeAudioFiles") private var shouldMergeAudioFiles = true

    var body: some View {
        Form {
            Toggle("Merge audio files", isOn: $shouldMergeAudioFiles)
        }
        .padding()
    }
}

extension NSWorkspace {
    func openSystemSettings() {
        guard let url = urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else {
            assertionFailure("Failed to get System Settings app URL")
            return
        }

        openApplication(at: url, configuration: .init())
    }
}

#if DEBUG
#Preview {
    RootView()
}
#endif
