import SwiftUI
import AudioToolbox
import OSLog
import AVFoundation

struct AudioProcess: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case process
        case app
    }
    var id: pid_t
    var kind: Kind
    var name: String
    var audioActive: Bool
    var bundleID: String?
    var bundleURL: URL?
    var objectID: AudioObjectID
}

extension AudioProcess {
    var icon: NSImage {
        // For system audio, always use speaker icon
        if let systemIcon = NSImage(systemSymbolName: "speaker.wave.3", accessibilityDescription: "System Audio") {
            systemIcon.size = NSSize(width: 32, height: 32)
            return systemIcon
        } else {
            // Fallback to generic application icon
            let fallbackIcon = NSWorkspace.shared.icon(for: .applicationBundle)
            fallbackIcon.size = NSSize(width: 32, height: 32)
            return fallbackIcon
        }
    }
    
    static func systemAudioProcess() -> AudioProcess {
        return AudioProcess(
            id: -1, // Special ID for system audio
            kind: .app,
            name: "System Audio",
            audioActive: true,
            bundleID: nil,
            bundleURL: nil,
            objectID: AudioObjectID.unknown // Will be handled specially
        )
    }
}

extension String: @retroactive LocalizedError {
    public var errorDescription: String? { self }
}

@Observable
final class ProcessTap {

    typealias InvalidationHandler = (ProcessTap) -> Void

    let process: AudioProcess
    let muteWhenRunning: Bool
    private let logger: Logger

    private(set) var errorMessage: String? = nil

    init(process: AudioProcess, muteWhenRunning: Bool = false) {
        self.process = process
        self.muteWhenRunning = muteWhenRunning
        self.logger = Logger(subsystem: kAppSubsystem, category: "\(String(describing: ProcessTap.self))(\(process.name))")
    }

    @ObservationIgnored
    private var processTapID: AudioObjectID = .unknown
    @ObservationIgnored
    private var aggregateDeviceID = AudioObjectID.unknown
    @ObservationIgnored
    private var deviceProcID: AudioDeviceIOProcID?
    @ObservationIgnored
    private(set) var tapStreamDescription: AudioStreamBasicDescription?
    @ObservationIgnored
    private(set) var actualSampleRate: Double?
    @ObservationIgnored
    private var invalidationHandler: InvalidationHandler?

    @ObservationIgnored
    private(set) var activated = false

    func activate() {
        guard !activated else { return }
        activated = true

        logger.debug(#function)

        self.errorMessage = nil

        do {
            try prepare(for: process.objectID)
        } catch {
            logger.error("\(error, privacy: .public)")
            self.errorMessage = error.localizedDescription
        }
    }

    func invalidate() {
        guard activated else { return }
        defer { activated = false }

        logger.debug(#function)

        invalidationHandler?(self)
        self.invalidationHandler = nil

        if aggregateDeviceID.isValid {
            var err = AudioDeviceStop(aggregateDeviceID, deviceProcID)
            if err != noErr { logger.warning("Failed to stop aggregate device: \(err, privacy: .public)") }

            if let deviceProcID {
                err = AudioDeviceDestroyIOProcID(aggregateDeviceID, deviceProcID)
                if err != noErr { logger.warning("Failed to destroy device I/O proc: \(err, privacy: .public)") }
                self.deviceProcID = nil
            }

            err = AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            if err != noErr {
                logger.warning("Failed to destroy aggregate device: \(err, privacy: .public)")
            }
            aggregateDeviceID = .unknown
        }

        if processTapID.isValid {
            let err = AudioHardwareDestroyProcessTap(processTapID)
            if err != noErr {
                logger.warning("Failed to destroy audio tap: \(err, privacy: .public)")
            }
            self.processTapID = .unknown
        }
    }

    private func prepare(for objectID: AudioObjectID) throws {
        errorMessage = nil

        let systemOutputID = try AudioDeviceID.readDefaultSystemOutputDevice()
        let outputUID = try systemOutputID.readDeviceUID()
        let aggregateUID = UUID().uuidString

        // This is now always system audio capture
        // Get all currently active audio processes and create a tap that includes all of them
        let allProcessObjectIDs = try AudioObjectID.readProcessList()
        
        // Filter to only processes that are actually producing audio
        let activeAudioProcesses = allProcessObjectIDs.filter { objectID in
            objectID.readProcessIsRunning()
        }
        
        // If no active processes, fall back to all processes
        let processesToTap = activeAudioProcesses.isEmpty ? allProcessObjectIDs : activeAudioProcesses
        
        guard !processesToTap.isEmpty else {
            throw "No audio processes available for system audio capture"
        }
        
        let tapDescription = CATapDescription(stereoMixdownOfProcesses: processesToTap)
        tapDescription.uuid = UUID()
        tapDescription.muteBehavior = muteWhenRunning ? .mutedWhenTapped : .unmuted
        
        var tapID: AUAudioObjectID = .unknown
        var err = AudioHardwareCreateProcessTap(tapDescription, &tapID)

        guard err == noErr else {
            throw "System audio tap creation failed with error \(err)"
        }

        logger.debug("Created system audio process tap #\(tapID, privacy: .public) for \(processesToTap.count) processes")

        self.processTapID = tapID
        
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "SystemAudioTap",
            kAudioAggregateDeviceUIDKey: aggregateUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [
                    kAudioSubDeviceUIDKey: outputUID
                ]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: tapDescription.uuid.uuidString
                ]
            ]
        ]

        self.tapStreamDescription = try tapID.readAudioTapStreamBasicDescription()

        aggregateDeviceID = AudioObjectID.unknown
        err = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateDeviceID)
        guard err == noErr else {
            throw "Failed to create aggregate device for system audio: \(err)"
        }

        logger.debug("Created system audio aggregate device #\(self.aggregateDeviceID, privacy: .public)")

        // Read all available sample rate information for debugging
        logger.warning("=== SAMPLE RATE DIAGNOSTIC ===")
        logger.warning("Tap format sample rate: \(self.tapStreamDescription?.mSampleRate ?? 0, privacy: .public) Hz")

        if let nominalRate = try? aggregateDeviceID.readNominalSampleRate(), nominalRate > 0 {
            logger.warning("Aggregate device NOMINAL sample rate: \(nominalRate, privacy: .public) Hz")
        }

        if let actualRate = try? aggregateDeviceID.readActualSampleRate(), actualRate > 0 {
            logger.warning("Aggregate device ACTUAL sample rate: \(actualRate, privacy: .public) Hz")
        }

        if let inputFormat = try? aggregateDeviceID.readInputStreamFormat() {
            logger.warning("Aggregate device INPUT stream format: \(inputFormat.mSampleRate, privacy: .public) Hz, \(inputFormat.mChannelsPerFrame, privacy: .public) ch, \(inputFormat.mBitsPerChannel, privacy: .public) bits")
        }

        if let outputFormat = try? aggregateDeviceID.readOutputStreamFormat() {
            logger.warning("Aggregate device OUTPUT stream format: \(outputFormat.mSampleRate, privacy: .public) Hz, \(outputFormat.mChannelsPerFrame, privacy: .public) ch")
        }

        // Also read the system output device sample rate for comparison
        if let systemOutputID = try? AudioDeviceID.readDefaultSystemOutputDevice(),
           let systemRate = try? systemOutputID.readNominalSampleRate() {
            logger.warning("System output device sample rate: \(systemRate, privacy: .public) Hz")
        }

        // Log buffer frame sizes
        if let aggregateBufferSize = try? aggregateDeviceID.readBufferFrameSize() {
            logger.warning("Aggregate device buffer frame size: \(aggregateBufferSize, privacy: .public)")
        }
        if let systemOutputID = try? AudioDeviceID.readDefaultSystemOutputDevice(),
           let systemBufferSize = try? systemOutputID.readBufferFrameSize() {
            logger.warning("System output device buffer frame size: \(systemBufferSize, privacy: .public)")
        }
        logger.warning("=== END SAMPLE RATE DIAGNOSTIC ===")

        // IMPORTANT: The aggregate device's main sub-device is the system output device,
        // so the aggregate device operates at the system output device's sample rate.
        // We should use the SYSTEM OUTPUT DEVICE rate as the primary source, since it's
        // more likely to be accurate than the aggregate device properties which may be delayed.

        // Priority: system output actual > aggregate actual > aggregate nominal > system output nominal > tap format
        var determinedRate: Double? = nil
        var rateSource: String = "unknown"

        // First try system output device's actual rate (most reliable)
        if let systemActualRate = try? systemOutputID.readActualSampleRate(), systemActualRate > 0 {
            determinedRate = systemActualRate
            rateSource = "system output device ACTUAL rate"
        }
        // Then try aggregate device actual rate
        else if let actualRate = try? aggregateDeviceID.readActualSampleRate(), actualRate > 0 {
            determinedRate = actualRate
            rateSource = "aggregate device ACTUAL rate"
        }
        // Then try aggregate device nominal rate
        else if let nominalRate = try? aggregateDeviceID.readNominalSampleRate(), nominalRate > 0 {
            determinedRate = nominalRate
            rateSource = "aggregate device NOMINAL rate"
        }
        // Then try system output device nominal rate
        else if let systemNominalRate = try? systemOutputID.readNominalSampleRate(), systemNominalRate > 0 {
            determinedRate = systemNominalRate
            rateSource = "system output device NOMINAL rate"
        }
        // Finally fall back to tap format
        else {
            determinedRate = tapStreamDescription?.mSampleRate
            rateSource = "tap format (fallback)"
        }

        self.actualSampleRate = determinedRate
        logger.warning("Selected sample rate: \(determinedRate ?? 0, privacy: .public) Hz from \(rateSource, privacy: .public)")

        logger.warning("FINAL actualSampleRate that will be used: \(self.actualSampleRate ?? 0, privacy: .public) Hz")
    }

    func run(on queue: DispatchQueue, ioBlock: @escaping AudioDeviceIOBlock, invalidationHandler: @escaping InvalidationHandler) throws {
        assert(activated, "\(#function) called with inactive tap!")
        assert(self.invalidationHandler == nil, "\(#function) called with tap already active!")

        errorMessage = nil

        logger.debug("Run tap!")

        self.invalidationHandler = invalidationHandler

        var err = AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, queue, ioBlock)
        guard err == noErr else { throw "Failed to create device I/O proc: \(err)" }

        err = AudioDeviceStart(aggregateDeviceID, deviceProcID)
        guard err == noErr else { throw "Failed to start audio device: \(err)" }
    }

    deinit { invalidate() }

}

@Observable
final class ProcessTapRecorder {

    let fileURL: URL
    let process: AudioProcess
    private let queue = DispatchQueue(label: "ProcessTapRecorder", qos: .userInitiated)
    private let logger: Logger

    @ObservationIgnored
    private weak var _tap: ProcessTap?

    private(set) var isRecording = false
    private let sampleRate: Double?

    // Diagnostic tracking
    @ObservationIgnored
    private var totalFramesWritten: UInt64 = 0
    @ObservationIgnored
    private var recordingStartTime: CFAbsoluteTime = 0
    @ObservationIgnored
    private var firstSampleTime: Float64?
    @ObservationIgnored
    private var lastSampleTime: Float64?
    @ObservationIgnored
    private var configuredSampleRate: Double = 0
    @ObservationIgnored
    private var firstCallbackTime: CFAbsoluteTime = 0
    @ObservationIgnored
    private var callbackCount: Int = 0

    // Sample rate detection
    @ObservationIgnored
    private var sampleRateWarningLogged: Bool = false

    init(fileURL: URL, tap: ProcessTap, sampleRate: Double? = nil) {
        self.process = tap.process
        self.fileURL = fileURL
        self._tap = tap
        self.sampleRate = sampleRate
        self.logger = Logger(subsystem: kAppSubsystem, category: "\(String(describing: ProcessTapRecorder.self))(\(fileURL.lastPathComponent))")
    }

    private var tap: ProcessTap {
        get throws {
            guard let _tap else { throw "Process tab unavailable" }
            return _tap
        }
    }

    @ObservationIgnored
    private var currentFile: AVAudioFile?

    func start() throws {
        logger.debug(#function)

        guard !isRecording else {
            logger.warning("\(#function, privacy: .public) while already recording")
            return
        }

        let tap = try tap

        if !tap.activated { tap.activate() }

        guard var streamDescription = tap.tapStreamDescription else {
            throw "Tap stream description not available."
        }

        // Use actual sample rate if provided, otherwise fall back to tap format rate
        let actualRate = sampleRate ?? streamDescription.mSampleRate

        logger.info("Tap stream description sample rate: \(streamDescription.mSampleRate, privacy: .public)")
        logger.info("Tap format details: formatID=\(streamDescription.mFormatID, privacy: .public), formatFlags=\(streamDescription.mFormatFlags, privacy: .public)")
        logger.info("Tap format details: bytesPerPacket=\(streamDescription.mBytesPerPacket, privacy: .public), framesPerPacket=\(streamDescription.mFramesPerPacket, privacy: .public)")
        logger.info("Tap format details: bytesPerFrame=\(streamDescription.mBytesPerFrame, privacy: .public), channelsPerFrame=\(streamDescription.mChannelsPerFrame, privacy: .public), bitsPerChannel=\(streamDescription.mBitsPerChannel, privacy: .public)")
        logger.info("Actual sample rate to use: \(actualRate, privacy: .public)")

        // CRITICAL: Override the stream description's sample rate with the actual rate
        // The tap format may report wrong sample rate, but data comes at aggregate device rate
        streamDescription.mSampleRate = actualRate

        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw "Failed to create AVAudioFormat."
        }

        logger.info("AVAudioFormat sample rate (corrected): \(format.sampleRate, privacy: .public)")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: actualRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
        ]
        let file = try AVAudioFile(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)

        self.currentFile = file

        // Reset diagnostic tracking
        self.totalFramesWritten = 0
        self.recordingStartTime = CFAbsoluteTimeGetCurrent()
        self.firstSampleTime = nil
        self.lastSampleTime = nil
        self.configuredSampleRate = actualRate
        self.firstCallbackTime = 0
        self.callbackCount = 0
        self.sampleRateWarningLogged = false

        try tap.run(on: queue) { [weak self] inNow, inInputData, inInputTime, outOutputData, inOutputTime in
            guard let self, let currentFile = self.currentFile else { return }
            do {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: inInputData, deallocator: nil) else {
                    throw "Failed to create PCM buffer"
                }

                let currentTime = CFAbsoluteTimeGetCurrent()
                self.callbackCount += 1

                // Track sample times for diagnostic
                let sampleTime = inInputTime.pointee.mSampleTime
                if self.firstSampleTime == nil {
                    self.firstSampleTime = sampleTime
                    self.firstCallbackTime = currentTime
                    self.logger.info("First buffer: sampleTime=\(sampleTime, privacy: .public), frames=\(buffer.frameLength, privacy: .public)")

                    // Log detailed format info on first callback
                    self.logger.info("Buffer format: sampleRate=\(buffer.format.sampleRate, privacy: .public), channels=\(buffer.format.channelCount, privacy: .public), interleaved=\(buffer.format.isInterleaved, privacy: .public)")

                    // Log AudioBufferList details
                    let bufferList = inInputData.pointee
                    self.logger.info("AudioBufferList: mNumberBuffers=\(bufferList.mNumberBuffers, privacy: .public)")
                    if bufferList.mNumberBuffers > 0 {
                        let firstBuffer = bufferList.mBuffers
                        self.logger.info("First AudioBuffer: mNumberChannels=\(firstBuffer.mNumberChannels, privacy: .public), mDataByteSize=\(firstBuffer.mDataByteSize, privacy: .public)")
                    }

                    // Calculate bytes per frame from raw data
                    if bufferList.mNumberBuffers > 0 && buffer.frameLength > 0 {
                        let bytesPerFrameFromData = bufferList.mBuffers.mDataByteSize / buffer.frameLength
                        self.logger.info("Calculated bytes per frame from data: \(bytesPerFrameFromData, privacy: .public)")
                    }
                }
                self.lastSampleTime = sampleTime + Float64(buffer.frameLength)
                self.totalFramesWritten += UInt64(buffer.frameLength)

                // Early sample rate mismatch detection (after ~50 callbacks, ~1 second)
                if self.callbackCount == 50 && !self.sampleRateWarningLogged {
                    let elapsedWallClock = currentTime - self.firstCallbackTime
                    if elapsedWallClock > 0.5 {
                        let actualRateFromFrames = Double(self.totalFramesWritten) / elapsedWallClock
                        let ratio = actualRateFromFrames / self.configuredSampleRate

                        self.logger.warning("Early sample rate check: configured=\(self.configuredSampleRate, privacy: .public)Hz, measured=\(actualRateFromFrames, privacy: .public)Hz, ratio=\(ratio, privacy: .public)")

                        if ratio < 0.6 || ratio > 1.6 {
                            self.sampleRateWarningLogged = true
                            self.logger.error("CRITICAL: Sample rate mismatch detected! Configured \(self.configuredSampleRate, privacy: .public)Hz but receiving \(actualRateFromFrames, privacy: .public)Hz")
                            self.logger.error("Recording will play at \(ratio, privacy: .public)x speed. Consider using \(actualRateFromFrames, privacy: .public)Hz instead.")
                        }
                    }
                }

                // Log diagnostic every 100 callbacks (~2 seconds)
                if self.callbackCount % 100 == 0 {
                    let elapsedWallClock = currentTime - self.firstCallbackTime
                    let elapsedSampleTime = sampleTime - (self.firstSampleTime ?? 0)
                    let impliedRateFromSampleTime = elapsedSampleTime / elapsedWallClock
                    let impliedRateFromFrames = Double(self.totalFramesWritten) / elapsedWallClock
                    self.logger.info("Callback #\(self.callbackCount, privacy: .public): frames=\(self.totalFramesWritten, privacy: .public), wallClock=\(elapsedWallClock, privacy: .public)s, rateFromFrames=\(impliedRateFromFrames, privacy: .public)Hz, rateFromSampleTime=\(impliedRateFromSampleTime, privacy: .public)Hz")
                }

                try currentFile.write(from: buffer)
            } catch {
                logger.error("\(error, privacy: .public)")
            }
        } invalidationHandler: { [weak self] tap in
            guard let self else { return }
            handleInvalidation()
        }

        isRecording = true
    }

    func stop() {
        logger.debug(#function)

        guard isRecording else { return }

        // Calculate diagnostic info before stopping
        let wallClockDuration = CFAbsoluteTimeGetCurrent() - recordingStartTime
        let preciseWallClockDuration = firstCallbackTime > 0 ? CFAbsoluteTimeGetCurrent() - firstCallbackTime : wallClockDuration
        let sampleTimeDuration: Float64
        if let first = firstSampleTime, let last = lastSampleTime {
            sampleTimeDuration = last - first
        } else {
            sampleTimeDuration = 0
        }

        // Log diagnostic summary
        logger.warning("=== RECORDING DIAGNOSTIC ===")
        logger.warning("Wall clock duration (from start): \(wallClockDuration, privacy: .public) seconds")
        logger.warning("Wall clock duration (from first callback): \(preciseWallClockDuration, privacy: .public) seconds")
        logger.warning("Total frames written: \(self.totalFramesWritten, privacy: .public)")
        logger.warning("Total callbacks: \(self.callbackCount, privacy: .public)")
        logger.warning("Configured sample rate: \(self.configuredSampleRate, privacy: .public) Hz")
        logger.warning("Sample time span (from timestamps): \(sampleTimeDuration, privacy: .public)")

        // Calculate actual sample rate from frames and wall clock time
        if preciseWallClockDuration > 0 {
            let actualSampleRateFromWallClock = Double(totalFramesWritten) / preciseWallClockDuration
            logger.warning("Actual sample rate (frames/wall_clock): \(actualSampleRateFromWallClock, privacy: .public) Hz")

            let speedRatio = actualSampleRateFromWallClock / configuredSampleRate
            logger.warning("Speed ratio (actual/configured): \(speedRatio, privacy: .public)x")

            if speedRatio > 1.8 && speedRatio < 2.2 {
                logger.error("BUG CONFIRMED: Audio data arriving at ~2x expected rate!")
                logger.error("File will play at 2x speed. Need to use \(actualSampleRateFromWallClock, privacy: .public) Hz instead of \(self.configuredSampleRate, privacy: .public) Hz")
            } else if speedRatio > 1.2 {
                logger.error("BUG DETECTED: Audio data arriving at ~\(speedRatio, privacy: .public)x expected rate!")
            }
        }

        // Also check sample time rate
        if sampleTimeDuration > 0 && preciseWallClockDuration > 0 {
            let sampleTimeRate = sampleTimeDuration / preciseWallClockDuration
            logger.warning("Sample time rate (sample_time_span/wall_clock): \(sampleTimeRate, privacy: .public) Hz")
        }

        // Calculate expected file duration vs what it should be
        let expectedFileDuration = Double(totalFramesWritten) / configuredSampleRate
        logger.warning("Expected file duration (frames/configured_rate): \(expectedFileDuration, privacy: .public) seconds")
        logger.warning("Actual recording duration (wall clock): \(preciseWallClockDuration, privacy: .public) seconds")
        if preciseWallClockDuration > 0 {
            let durationRatio = expectedFileDuration / preciseWallClockDuration
            logger.warning("Duration ratio (file/actual): \(durationRatio, privacy: .public)x - if <1, audio will be sped up")
        }
        logger.warning("=== END DIAGNOSTIC ===")

        // Mark as not recording first to prevent new writes
        isRecording = false

        // Close file before invalidating tap
        currentFile = nil

        // Invalidate tap on the queue to ensure proper cleanup sequence
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.tap.invalidate()
            } catch {
                self.logger.error("Stop failed: \(error, privacy: .public)")
            }
        }
    }

    private func handleInvalidation() {
        guard isRecording else { return }

        logger.debug(#function)
    }

}
