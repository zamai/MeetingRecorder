import AVFoundation
import Accelerate
import Foundation

/// Analyzes audio files to verify recording quality and detect sample rate issues
class AudioAnalyzer {

    // MARK: - Duration Analysis

    /// Get the duration of an audio file in seconds
    func getDuration(fileURL: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: fileURL)
        let sampleRate = file.processingFormat.sampleRate
        let frameCount = file.length
        return Double(frameCount) / sampleRate
    }

    /// Verify file duration matches expected (within tolerance)
    /// - Parameters:
    ///   - fileURL: URL of the audio file to analyze
    ///   - expected: Expected duration in seconds
    ///   - tolerance: Acceptable deviation as a fraction (0.1 = 10%)
    /// - Returns: True if duration is within tolerance
    func verifyDuration(fileURL: URL, expected: TimeInterval, tolerance: Double = 0.1) throws -> Bool {
        let actualDuration = try getDuration(fileURL: fileURL)
        let deviation = abs(actualDuration - expected) / expected
        return deviation <= tolerance
    }

    /// Calculate the speed ratio (actual/expected duration)
    /// A ratio of 0.5 indicates 2x speed bug, 2.0 indicates 0.5x speed bug
    func calculateSpeedRatio(fileURL: URL, expectedDuration: TimeInterval) throws -> Double {
        let actualDuration = try getDuration(fileURL: fileURL)
        return actualDuration / expectedDuration
    }

    // MARK: - Sample Rate Analysis

    /// Get the sample rate of an audio file
    func getSampleRate(fileURL: URL) throws -> Double {
        let file = try AVAudioFile(forReading: fileURL)
        return file.processingFormat.sampleRate
    }

    /// Verify file sample rate matches expected
    func verifySampleRate(fileURL: URL, expected: Double, tolerance: Double = 1.0) throws -> Bool {
        let actualRate = try getSampleRate(fileURL: fileURL)
        return abs(actualRate - expected) <= tolerance
    }

    // MARK: - Frequency Analysis (FFT)

    /// Extract the dominant frequency from an audio file using FFT
    /// - Parameter fileURL: URL of the audio file to analyze
    /// - Returns: The dominant frequency in Hz
    func dominantFrequency(fileURL: URL) throws -> Double {
        let file = try AVAudioFile(forReading: fileURL)
        let sampleRate = file.processingFormat.sampleRate

        // Read a portion of the file for analysis (1 second or less)
        let framesToRead = min(file.length, AVAudioFramePosition(sampleRate))

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(framesToRead)) else {
            throw AudioAnalyzerError.failedToCreateBuffer
        }

        // Seek to middle of file for better analysis
        let middlePosition = file.length / 2
        file.framePosition = max(0, middlePosition - framesToRead / 2)

        try file.read(into: buffer)

        guard let floatData = buffer.floatChannelData?[0] else {
            throw AudioAnalyzerError.failedToReadAudioData
        }

        return try performFFT(samples: floatData, frameCount: Int(buffer.frameLength), sampleRate: sampleRate)
    }

    /// Verify audio contains expected frequency
    /// - Parameters:
    ///   - fileURL: URL of the audio file to analyze
    ///   - expected: Expected dominant frequency in Hz
    ///   - tolerance: Acceptable deviation in Hz
    /// - Returns: True if dominant frequency is within tolerance of expected
    func verifyFrequency(fileURL: URL, expected: Double, tolerance: Double = 50.0) throws -> Bool {
        let dominant = try dominantFrequency(fileURL: fileURL)
        return abs(dominant - expected) <= tolerance
    }

    // MARK: - FFT Implementation

    private func performFFT(samples: UnsafePointer<Float>, frameCount: Int, sampleRate: Double) throws -> Double {
        // Find the nearest power of 2 for FFT
        let log2n = vDSP_Length(log2(Double(frameCount)))
        let fftSize = Int(1 << log2n)

        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            throw AudioAnalyzerError.failedToCreateFFTSetup
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        // Prepare input data
        var realPart = [Float](repeating: 0, count: fftSize / 2)
        var imagPart = [Float](repeating: 0, count: fftSize / 2)

        // Copy samples and apply window function
        var windowedSamples = [Float](repeating: 0, count: fftSize)
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        for i in 0..<min(frameCount, fftSize) {
            windowedSamples[i] = samples[i] * window[i]
        }

        // Convert to split complex format
        windowedSamples.withUnsafeBufferPointer { samplesPtr in
            var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
            samplesPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
            }
        }

        // Perform FFT
        var splitComplex = DSPSplitComplex(realp: &realPart, imagp: &imagPart)
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

        // Find peak (skip DC component at index 0)
        var maxMagnitude: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(&magnitudes + 1, 1, &maxMagnitude, &maxIndex, vDSP_Length(fftSize / 2 - 1))
        maxIndex += 1 // Adjust for skipping DC

        // Convert bin index to frequency
        let frequencyResolution = sampleRate / Double(fftSize)
        let dominantFrequency = Double(maxIndex) * frequencyResolution

        return dominantFrequency
    }

    // MARK: - Comprehensive Analysis

    /// Perform comprehensive analysis of a recording
    struct AnalysisResult {
        let duration: TimeInterval
        let sampleRate: Double
        let dominantFrequency: Double
        let speedRatio: Double? // Only if expectedDuration provided
        let channelCount: Int
    }

    func analyze(fileURL: URL, expectedDuration: TimeInterval? = nil) throws -> AnalysisResult {
        let file = try AVAudioFile(forReading: fileURL)

        let duration = Double(file.length) / file.processingFormat.sampleRate
        let sampleRate = file.processingFormat.sampleRate
        let channelCount = Int(file.processingFormat.channelCount)
        let dominantFreq = try dominantFrequency(fileURL: fileURL)

        let speedRatio: Double?
        if let expected = expectedDuration {
            speedRatio = duration / expected
        } else {
            speedRatio = nil
        }

        return AnalysisResult(
            duration: duration,
            sampleRate: sampleRate,
            dominantFrequency: dominantFreq,
            speedRatio: speedRatio,
            channelCount: channelCount
        )
    }
}

enum AudioAnalyzerError: Error, LocalizedError {
    case failedToCreateBuffer
    case failedToReadAudioData
    case failedToCreateFFTSetup

    var errorDescription: String? {
        switch self {
        case .failedToCreateBuffer:
            return "Failed to create audio buffer for analysis"
        case .failedToReadAudioData:
            return "Failed to read audio data from file"
        case .failedToCreateFFTSetup:
            return "Failed to create FFT setup"
        }
    }
}
