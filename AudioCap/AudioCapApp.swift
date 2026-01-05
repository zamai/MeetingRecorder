import SwiftUI

let kAppSubsystem = "codes.rambo.AudioCap"

@main
struct AudioCapApp: App {
    var body: some Scene {
        MenuBarExtra {
            RootView()
        } label: {
            Image(systemName: "mic.circle")
        }
    }
}
