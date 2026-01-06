import XCTest
import AVFoundation
import AudioToolbox
@testable import MeetingRecorder

/// Integration tests for audio recording that guard against sample rate mismatches
/// These tests verify that recordings have correct duration and frequency content
final class AudioIntegrationTests: XCTestCase {

    var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Create temp directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MeetingRecorderTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Clean up temp files
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Sine Wave Generator Tests

    /// Test that SineWaveGenerator creates audio with correct duration
    func testSineWaveGeneratorDuration() throws {
        let expectedDuration: TimeInterval = 3.0
        let generator = SineWaveGenerator(frequency: 1000, sampleRate: 48000, duration: expectedDuration)

        let outputURL = tempDirectory.appendingPathComponent("test_sine.m4a")
        try generator.writeToFile(url: outputURL)

        let analyzer = AudioAnalyzer()
        let actualDuration = try analyzer.getDuration(fileURL: outputURL)

        // Duration should match within 5%
        XCTAssertEqual(actualDuration, expectedDuration, accuracy: expectedDuration * 0.05,
                       "Generated audio duration should match expected")
    }

    /// Test that SineWaveGenerator creates audio with correct frequency
    func testSineWaveGeneratorFrequency() throws {
        let expectedFrequency: Double = 1000.0
        let generator = SineWaveGenerator(frequency: expectedFrequency, sampleRate: 48000, duration: 2.0)

        // Write as WAV for more accurate frequency analysis
        let outputURL = tempDirectory.appendingPathComponent("test_sine.wav")
        try generator.writeToWAVFile(url: outputURL)

        let analyzer = AudioAnalyzer()
        let dominantFreq = try analyzer.dominantFrequency(fileURL: outputURL)

        // Frequency should be within 50 Hz
        XCTAssertEqual(dominantFreq, expectedFrequency, accuracy: 50,
                       "Dominant frequency should match expected sine wave frequency")
    }

    // MARK: - Audio Analyzer Tests

    /// Test that AudioAnalyzer correctly detects sample rate
    func testAudioAnalyzerSampleRate() throws {
        let expectedSampleRate: Double = 48000
        let generator = SineWaveGenerator(frequency: 440, sampleRate: expectedSampleRate, duration: 1.0)

        let outputURL = tempDirectory.appendingPathComponent("test_sample_rate.m4a")
        try generator.writeToFile(url: outputURL)

        let analyzer = AudioAnalyzer()
        let actualSampleRate = try analyzer.getSampleRate(fileURL: outputURL)

        XCTAssertEqual(actualSampleRate, expectedSampleRate, accuracy: 1.0,
                       "Sample rate should match expected")
    }

    /// Test comprehensive analysis
    func testAudioAnalyzerComprehensiveAnalysis() throws {
        let expectedDuration: TimeInterval = 2.0
        let expectedFrequency: Double = 880.0 // A5 note
        let expectedSampleRate: Double = 48000

        let generator = SineWaveGenerator(
            frequency: expectedFrequency,
            sampleRate: expectedSampleRate,
            duration: expectedDuration
        )

        let outputURL = tempDirectory.appendingPathComponent("test_comprehensive.wav")
        try generator.writeToWAVFile(url: outputURL)

        let analyzer = AudioAnalyzer()
        let result = try analyzer.analyze(fileURL: outputURL, expectedDuration: expectedDuration)

        XCTAssertEqual(result.duration, expectedDuration, accuracy: 0.1)
        XCTAssertEqual(result.sampleRate, expectedSampleRate, accuracy: 1.0)
        XCTAssertEqual(result.dominantFrequency, expectedFrequency, accuracy: 50)
        XCTAssertEqual(result.channelCount, 2) // Stereo

        // Speed ratio should be ~1.0 (no 2x speed bug)
        if let speedRatio = result.speedRatio {
            XCTAssertEqual(speedRatio, 1.0, accuracy: 0.1,
                           "Speed ratio should be 1.0 (no speed bug)")
        }
    }

    // MARK: - Sample Rate Detection Tests

    /// Test that ProcessTap correctly detects system sample rate
    func testProcessTapSampleRateDetection() throws {
        let systemAudioProcess = AudioProcess.systemAudioProcess()
        let tap = ProcessTap(process: systemAudioProcess, muteWhenRunning: false)

        tap.activate()
        defer { tap.invalidate() }

        // Verify we got a sample rate
        XCTAssertNotNil(tap.actualSampleRate, "ProcessTap should detect a sample rate")

        if let actualRate = tap.actualSampleRate {
            // Should be a standard rate
            let standardRates: Set<Double> = [24000, 44100, 48000, 88200, 96000]
            XCTAssertTrue(standardRates.contains(actualRate),
                          "Detected sample rate \(actualRate) should be a standard rate")
        }
    }

    /// Test that detected sample rate matches system output device
    func testSampleRateMatchesSystemOutput() throws {
        // Get system output device rate
        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()
        let systemRate = try systemOutputID.readNominalSampleRate()

        // Get tap's detected rate
        let systemAudioProcess = AudioProcess.systemAudioProcess()
        let tap = ProcessTap(process: systemAudioProcess, muteWhenRunning: false)
        tap.activate()
        defer { tap.invalidate() }

        guard let tapRate = tap.actualSampleRate else {
            XCTFail("Could not get tap sample rate")
            return
        }

        // The tap rate should match system output rate (within 10% tolerance)
        // This is the key check for the 2x speed bug
        let ratio = tapRate / systemRate
        XCTAssertEqual(ratio, 1.0, accuracy: 0.1,
                       "Tap sample rate (\(tapRate)) should match system output rate (\(systemRate))")
    }

    // MARK: - Recording Duration Tests

    /// Test that ProcessTapRecorder creates files with correct sample rate
    func testProcessTapRecorderSampleRate() throws {
        let systemAudioProcess = AudioProcess.systemAudioProcess()
        let tap = ProcessTap(process: systemAudioProcess, muteWhenRunning: false)
        tap.activate()

        guard let expectedRate = tap.actualSampleRate else {
            tap.invalidate()
            XCTFail("Could not determine sample rate")
            return
        }

        let outputURL = tempDirectory.appendingPathComponent("test_recording.m4a")
        let recorder = ProcessTapRecorder(fileURL: outputURL, tap: tap, sampleRate: expectedRate)

        // Record briefly
        try recorder.start()

        let recordDuration: TimeInterval = 2.0
        let expectation = XCTestExpectation(description: "Recording completes")

        DispatchQueue.main.asyncAfter(deadline: .now() + recordDuration) {
            recorder.stop()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: recordDuration + 2.0)

        // Wait for file to be written
        Thread.sleep(forTimeInterval: 0.5)

        // Verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path),
                      "Recording file should exist")

        // Verify sample rate matches
        let analyzer = AudioAnalyzer()
        let fileSampleRate = try analyzer.getSampleRate(fileURL: outputURL)

        XCTAssertEqual(fileSampleRate, expectedRate, accuracy: 1.0,
                       "File sample rate should match configured rate")
    }

    // MARK: - Speed Bug Detection Tests

    /// This test would detect the 2x speed bug by verifying recording duration
    /// If the sample rate is misconfigured, the file duration won't match wall clock time
    func testRecordingDurationMatchesWallClock() throws {
        let systemAudioProcess = AudioProcess.systemAudioProcess()
        let tap = ProcessTap(process: systemAudioProcess, muteWhenRunning: false)
        tap.activate()

        guard let sampleRate = tap.actualSampleRate else {
            tap.invalidate()
            XCTFail("Could not determine sample rate")
            return
        }

        let outputURL = tempDirectory.appendingPathComponent("duration_test.m4a")
        let recorder = ProcessTapRecorder(fileURL: outputURL, tap: tap, sampleRate: sampleRate)

        let expectedDuration: TimeInterval = 3.0

        // Record for expected duration
        try recorder.start()
        let startTime = CFAbsoluteTimeGetCurrent()

        let expectation = XCTestExpectation(description: "Recording completes")

        DispatchQueue.main.asyncAfter(deadline: .now() + expectedDuration) {
            recorder.stop()
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: expectedDuration + 2.0)
        let actualWallClockDuration = CFAbsoluteTimeGetCurrent() - startTime

        // Wait for file to be written
        Thread.sleep(forTimeInterval: 0.5)

        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            XCTFail("Recording file was not created")
            return
        }

        let analyzer = AudioAnalyzer()
        let fileDuration = try analyzer.getDuration(fileURL: outputURL)

        // File duration should approximately match wall clock duration
        // A 2x speed bug would make fileDuration = actualWallClockDuration / 2
        let speedRatio = fileDuration / actualWallClockDuration

        XCTAssertEqual(speedRatio, 1.0, accuracy: 0.15,
                       "Speed ratio should be ~1.0. Got \(speedRatio) - " +
                       "if ~0.5, this indicates the 2x speed bug. " +
                       "File duration: \(fileDuration)s, Wall clock: \(actualWallClockDuration)s")
    }

    // MARK: - Regression Guard Tests

    /// Regression test: Verify sample rate priority order is correct
    /// The fix uses system output actual rate first, which should match what the I/O callback delivers
    func testSampleRatePriorityOrder() throws {
        // Get system output device rates
        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()

        let nominalRate = try systemOutputID.readNominalSampleRate()

        // Actual rate may not be available on all devices
        let actualRate = try? systemOutputID.readActualSampleRate()

        // Create tap and check what rate it selects
        let systemAudioProcess = AudioProcess.systemAudioProcess()
        let tap = ProcessTap(process: systemAudioProcess, muteWhenRunning: false)
        tap.activate()
        defer { tap.invalidate() }

        guard let tapSelectedRate = tap.actualSampleRate else {
            XCTFail("Tap did not select a sample rate")
            return
        }

        // The selected rate should be either the actual rate (if available) or nominal rate
        if let actual = actualRate, actual > 0 {
            XCTAssertEqual(tapSelectedRate, actual, accuracy: 1.0,
                           "Tap should use system output ACTUAL rate when available")
        } else {
            XCTAssertEqual(tapSelectedRate, nominalRate, accuracy: 1.0,
                           "Tap should use system output NOMINAL rate as fallback")
        }
    }
}
