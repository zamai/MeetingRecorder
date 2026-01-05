import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

@MainActor
struct DualRecordingView: View {
    let tap: ProcessTap
    @Binding var recorder: ProcessTapRecorder?
    @Binding var micRecorder: MicrophoneRecorder?

    var body: some View {
        Section {
            HStack {
                if recorder?.isRecording ?? false || micRecorder?.isRecording ?? false {
                    Button("Stop Recording") {
                        stopBothRecorders()
                    }
                    .id("button")
                } else {
                    Button("Start Recording") {
                        Task {
                            await startRecordingFlow()
                        }
                    }
                    .id("button")
                }
            }
            .animation(.smooth, value: recorder?.isRecording)
            .animation(.smooth, value: micRecorder?.isRecording)
        } header: {
            HStack {
                RecordingIndicator(appIcon: tap.process.icon, isRecording: recorder?.isRecording ?? false || micRecorder?.isRecording ?? false)

                Text(getRecordingStatusText())
                    .font(.headline)
                    .contentTransition(.identity)
            }
        }
    }

    private func getRecordingStatusText() -> String {
        if recorder?.isRecording ?? false || micRecorder?.isRecording ?? false {
            return "Recording System Audio + Microphone"
        } else {
            return "Ready to Record System Audio + Microphone"
        }
    }

    private func startRecordingFlow() async {
        do {
            createRecorders()
            let permissionsGranted = await requestPermissions()
            if permissionsGranted {
                try startBothRecorders()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func createRecorders() {
        let timestamp = Int(Date.now.timeIntervalSinceReferenceDate)

        let micFilename = "Microphone-\(timestamp)"
        let micAudioFileURL = URL.applicationSupport.appendingPathComponent(micFilename).appendingPathExtension(for: UTType(mimeType: "audio/mp4")!)
        let newMicRecorder = MicrophoneRecorder(fileURL: micAudioFileURL)
        self.micRecorder = newMicRecorder

        // Don't access audioEngine.inputNode here - it can cause premature audio session initialization
        // Use standard sample rate; the tap will use its native format
        let systemFilename = "SystemAudio-\(timestamp)"
        let systemAudioFileURL = URL.applicationSupport.appendingPathComponent(systemFilename).appendingPathExtension(for: UTType(mimeType: "audio/mp4")!)
        let newSystemRecorder = ProcessTapRecorder(fileURL: systemAudioFileURL, tap: tap, sampleRate: nil)
        self.recorder = newSystemRecorder
    }

    private func requestPermissions() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startBothRecorders() throws {
        try recorder?.start()
        try micRecorder?.start()
    }

    private func stopBothRecorders() {
        recorder?.stop()
        micRecorder?.stop()
    }

    private func handlingErrors(perform block: () throws -> Void) {
        do {
            try block()
        } catch {
            /// "handling" in the function name might not be entirely true 😅
            NSAlert(error: error).runModal()
        }
    }
}
