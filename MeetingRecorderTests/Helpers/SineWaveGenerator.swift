import AVFoundation
import Foundation

/// Generates sine wave test audio for integration testing
class SineWaveGenerator {
    let frequency: Double
    let sampleRate: Double
    let duration: TimeInterval
    let amplitude: Float

    init(frequency: Double = 1000.0, sampleRate: Double = 48000.0, duration: TimeInterval = 5.0, amplitude: Float = 0.5) {
        self.frequency = frequency
        self.sampleRate = sampleRate
        self.duration = duration
        self.amplitude = amplitude
    }

    /// Generate an AVAudioPCMBuffer containing a sine wave
    func generateBuffer() -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let floatChannelData = buffer.floatChannelData else {
            return nil
        }

        let twoPi = 2.0 * Double.pi
        let angularFrequency = twoPi * frequency

        // Generate stereo sine wave
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let sample = Float(sin(angularFrequency * time)) * amplitude

            // Write to both channels (stereo)
            floatChannelData[0][frame] = sample
            floatChannelData[1][frame] = sample
        }

        return buffer
    }

    /// Write the sine wave to an audio file
    func writeToFile(url: URL) throws {
        guard let buffer = generateBuffer() else {
            throw SineWaveGeneratorError.failedToGenerateBuffer
        }

        // Create output file with AAC encoding (same as app uses)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    /// Write the sine wave as uncompressed WAV for easier analysis
    func writeToWAVFile(url: URL) throws {
        guard let buffer = generateBuffer() else {
            throw SineWaveGeneratorError.failedToGenerateBuffer
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw SineWaveGeneratorError.failedToCreateFormat
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}

enum SineWaveGeneratorError: Error, LocalizedError {
    case failedToGenerateBuffer
    case failedToCreateFormat

    var errorDescription: String? {
        switch self {
        case .failedToGenerateBuffer:
            return "Failed to generate audio buffer"
        case .failedToCreateFormat:
            return "Failed to create audio format"
        }
    }
}
