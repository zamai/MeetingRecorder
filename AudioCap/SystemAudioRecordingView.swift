import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

@MainActor
struct SystemAudioRecordingView: View {
    @State private var tap: ProcessTap?
    @State private var recorder: ProcessTapRecorder?
    @State private var micRecorder: MicrophoneRecorder?
    @State private var destinationURL: URL?
    @AppStorage("shouldMergeAudioFiles") private var shouldMergeAudioFiles = true
    @AppStorage("periodicSaveInterval") private var periodicSaveInterval: Double = 300.0 // 5 minutes default
    @State private var periodicSaveTimer: Timer?
    @State private var recordingStartTime: Date?

    var body: some View {
        VStack {
            if let tap {
                if let errorMessage = tap.errorMessage {
                    Text(errorMessage)
                        .font(.headline)
                        .foregroundStyle(.red)
                } else {
                    DualRecordingView(tap: tap, recorder: $recorder, micRecorder: $micRecorder)
                        .onChange(of: recorder?.isRecording) { wasRecording, isRecording in
                            /// Each recorder instance can only record a single file, so we create a new file/recorder when recording stops.
                            if wasRecording == true, isRecording == false {
                                saveRecording()
                                recorder = nil
                                micRecorder = nil
                            }
                        }
                }
            }
            
            Divider()
            
            Button(action: {
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = false
                
                if panel.runModal() == .OK {
                    if let url = panel.url {
                        destinationURL = url
                        UserDefaults.standard.destinationFolderURL = url
                    }
                }
            }) {
                Text("Destination: \(destinationURL?.path ?? "Not Set")")
            }
        }
        .task {
            destinationURL = UserDefaults.standard.destinationFolderURL
            _ = destinationURL?.startAccessingSecurityScopedResource()
            setupSystemAudioRecording()
        }
        .onDisappear {
            destinationURL?.stopAccessingSecurityScopedResource()
        }
    }

    private func setupSystemAudioRecording() {
        // Create the system audio process
        let systemAudioProcess = AudioProcess.systemAudioProcess()
        let newTap = ProcessTap(process: systemAudioProcess)
        self.tap = newTap
        newTap.activate()
    }
    
    private func saveRecording() {
        guard let destinationURL else { return }
        guard let micURL = micRecorder?.fileURL, let systemURL = recorder?.fileURL else { return }

        _ = destinationURL.startAccessingSecurityScopedResource()
        defer { destinationURL.stopAccessingSecurityScopedResource() }

        if shouldMergeAudioFiles {
            let timestamp = Int(Date.now.timeIntervalSinceReferenceDate)
            let outputURL = destinationURL.appendingPathComponent("Recording-\(timestamp).m4a")

            AudioMerger.merge(files: [micURL, systemURL], to: outputURL) { error in
                if let error {
                    NSAlert(error: error).runModal()
                } else {
                    // Clean up original files
                    try? FileManager.default.removeItem(at: micURL)
                    try? FileManager.default.removeItem(at: systemURL)
                }
            }
        } else {
            do {
                try FileManager.default.moveItem(at: micURL, to: destinationURL.appendingPathComponent(micURL.lastPathComponent))
                try FileManager.default.moveItem(at: systemURL, to: destinationURL.appendingPathComponent(systemURL.lastPathComponent))
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }
}

class AudioMerger {
    static func merge(files fileURLs: [URL], to outputURL: URL, completion: @escaping (Error?) -> Void) {
        Task {
            do {
                let composition = AVMutableComposition()

                for fileURL in fileURLs {
                    let asset = AVAsset(url: fileURL)
                    guard let assetTrack = try await asset.loadTracks(withMediaType: .audio).first else { continue }

                    let compositionTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                    let duration = try await asset.load(.duration)
                    try compositionTrack?.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: assetTrack, at: .zero)
                }

                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
                    completion(NSError(domain: "com.audiocap.merger", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create export session."]))
                    return
                }

                exportSession.outputURL = outputURL
                exportSession.outputFileType = .m4a

                await exportSession.export()

                let error = exportSession.error
                DispatchQueue.main.async {
                    completion(error)
                }
            } catch {
                DispatchQueue.main.async {
                    completion(error)
                }
            }
        }
    }
}

extension URL {
    static var applicationSupport: URL {
        do {
            let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let subdir = appSupport.appending(path: "AudioCap", directoryHint: .isDirectory)
            if !FileManager.default.fileExists(atPath: subdir.path) {
                try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            }
            return subdir
        } catch {
            assertionFailure("Failed to get application support directory: \(error)")

            return FileManager.default.temporaryDirectory
        }
    }
}

extension UserDefaults {
    public enum Keys {
        static let destinationFolderBookmark = "destinationFolderBookmark"
        static let mergeAudioFiles = "mergeAudioFiles"
    }

    var destinationFolderURL: URL? {
        get {
            guard let bookmarkData = data(forKey: Keys.destinationFolderBookmark) else {
                return nil
            }
            
            var isStale = false
            guard let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) else {
                return nil
            }
            
            if isStale {
                // Handle stale bookmark if needed
                return nil
            }
            
            return url
        }
        set {
            guard let url = newValue else {
                removeObject(forKey: Keys.destinationFolderBookmark)
                return
            }
            
            guard let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
                return
            }
            
            set(bookmarkData, forKey: Keys.destinationFolderBookmark)
        }
    }

    var shouldMergeAudioFiles: Bool {
        get { bool(forKey: Keys.mergeAudioFiles) }
        set { set(newValue, forKey: Keys.mergeAudioFiles) }
    }
}
