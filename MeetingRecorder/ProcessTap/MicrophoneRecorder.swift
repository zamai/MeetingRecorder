import SwiftUI
import AVFoundation
import OSLog

@Observable
final class MicrophoneRecorder {

    let fileURL: URL
    private let logger: Logger
    private let targetSampleRate: Double?
    let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?

    private(set) var isRecording = false

    init(fileURL: URL, sampleRate: Double? = nil) {
        self.fileURL = fileURL
        self.targetSampleRate = sampleRate
        self.logger = Logger(subsystem: kAppSubsystem, category: "\(String(describing: MicrophoneRecorder.self))(\(fileURL.lastPathComponent))")
    }
    
    func start() throws {
        logger.debug(#function)

        guard !isRecording else {
            logger.warning("\(#function, privacy: .public) while already recording")
            return
        }

        // Ensure engine is stopped before starting fresh
        if audioEngine.isRunning {
            logger.warning("Audio engine already running, stopping first")
            audioEngine.stop()
        }

        // Get the default microphone input
        let inputNode = audioEngine.inputNode
        
        // Get the hardware format directly to avoid format mismatch
        let inputFormat = inputNode.inputFormat(forBus: 0)
        logger.info("Microphone hardware format: \(inputFormat, privacy: .public)")

        // Use target sample rate if provided (to match system audio), otherwise use hardware rate
        let outputSampleRate = targetSampleRate ?? inputFormat.sampleRate
        logger.info("Microphone input sample rate: \(inputFormat.sampleRate, privacy: .public)")
        logger.info("Target sample rate: \(self.targetSampleRate ?? 0, privacy: .public)")
        logger.info("File output sample rate: \(outputSampleRate, privacy: .public)")

        // Create audio file for writing
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: outputSampleRate,
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

        // Mark as not recording first
        isRecording = false

        // Stop engine first, then remove tap (proper order)
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        // Close file last
        audioFile = nil

        logger.info("Microphone recording stopped")
    }
    
    deinit {
        stop()
    }
}