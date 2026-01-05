import SwiftUI

let kAppSubsystem = "codes.rambo.MeetingRecorder"

@main
struct MeetingRecorderApp: App {
    var body: some Scene {
        MenuBarExtra {
            RootView()
        } label: {
            Image(systemName: "mic.circle")
        }
    }
}
