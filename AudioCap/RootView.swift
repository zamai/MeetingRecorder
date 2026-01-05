import SwiftUI

@MainActor
struct RootView: View {
    @State private var settingsWindow: NSWindow?

    var body: some View {
        VStack(spacing: 12) {
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
