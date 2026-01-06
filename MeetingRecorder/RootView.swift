import SwiftUI

@MainActor
struct RootView: View {
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

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
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
