import SwiftUI
import AVFoundation
import OSLog

@Observable
final class MicrophoneRecorder {
    
    let fileURL: URL
    private let logger: Logger
    let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    
    private(set) var isRecording = false
    
    init(fileURL: URL) {
        self.fileURL = fileURL
        self.logger = Logger(subsystem: kAppSubsystem, category: "\(String(describing: MicrophoneRecorder.self))(\(fileURL.lastPathComponent))")
    }
    
    @MainActor
    func start() throws {
        logger.debug(#function)
        
        guard !isRecording else {
            logger.warning("\(#function, privacy: .public) while already recording")
            return
        }
        
        // Get the default microphone input
        let inputNode = audioEngine.inputNode
        
        // Get the hardware format directly to avoid format mismatch
        let inputFormat = inputNode.inputFormat(forBus: 0)
        logger.info("Microphone hardware format: \(inputFormat, privacy: .public)")
        
        // Create audio file for writing using the hardware format directly
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: inputFormat.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
        ]
        
        let file = try AVAudioFile(forWriting: fileURL, settings: settings)
        self.audioFile = file
        
        // Install tap on input node using the hardware format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, time in
            guard let self, let audioFile = self.audioFile else { return }
            
            do {
                // Direct write since we're using the same format
                try audioFile.write(from: buffer)
            } catch {
                self.logger.error("Failed to write microphone audio: \(error, privacy: .public)")
            }
        }
        
        // Start the audio engine
        try audioEngine.start()
        
        isRecording = true
        logger.info("Microphone recording started")
    }
    
    func stop() {
        logger.debug(#function)
        
        guard isRecording else { return }
        
        // Remove tap and stop engine
        audioEngine.inputNode.removeTap(onBus: 0)
        
        audioEngine.stop()
        audioFile = nil
        isRecording = false
        
        logger.info("Microphone recording stopped")
    }
    
    deinit {
        stop()
    }
}