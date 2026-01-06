import SwiftUI

let kAppSubsystem = "com.zamai.MeetingRecorder"

@Observable
final class RecordingState {
    static let shared = RecordingState()
    var isRecording = false
    var stopAction: (() -> Void)?
}

@main
struct MeetingRecorderApp: App {
    @State private var recordingState = RecordingState.shared

    init() {
        PostHogAnalytics.configure()
        PostHogAnalytics.trackFirstLaunchIfNeeded()
    }

    var body: some Scene {
        MenuBarExtra {
            RootView()
        } label: {
            if recordingState.isRecording {
                Image(systemName: "stop.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
            } else {
                Image(systemName: "mic.circle")
            }
        }
    }
}
