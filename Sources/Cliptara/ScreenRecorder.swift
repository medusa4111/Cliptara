import AVFoundation
import CoreGraphics
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit

enum ScreenRecordingState: Equatable {
    case idle
    case recording
    case paused
}

enum ScreenRecorderError: LocalizedError, Equatable {
    case alreadyRecording
    case stopInProgress
    case notRecording
    case notPaused
    case permissionDenied
    case microphonePermissionDenied
    case displayNotFound
    case streamSetupFailed
    case invalidOutputFile

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return Localizer.text("Запись уже идет.", "Recording is already in progress.")
        case .stopInProgress:
            return Localizer.text("Остановка записи уже выполняется.", "Recording stop is already in progress.")
        case .notRecording:
            return Localizer.text("Запись сейчас не идет.", "Recording is not running.")
        case .notPaused:
            return Localizer.text("Запись сейчас не на паузе.", "Recording is not paused.")
        case .permissionDenied:
            return Localizer.text(
                "Нет доступа к записи экрана. Разрешите доступ в Системных настройках.",
                "Screen Recording access is not granted. Enable it in System Settings."
            )
        case .microphonePermissionDenied:
            return Localizer.text(
                "Нет доступа к микрофону. Разрешите доступ для Cliptara в разделе «Конфиденциальность и безопасность → Микрофон».",
                "Microphone access is denied. Allow Cliptara in Privacy & Security → Microphone."
            )
        case .displayNotFound:
            return Localizer.text("Не удалось найти экран для записи.", "Could not find a display to record.")
        case .streamSetupFailed:
            return Localizer.text("Не удалось настроить захват экрана.", "Could not configure screen capture.")
        case .invalidOutputFile:
            return Localizer.text(
                "Видео не удалось корректно сохранить. Попробуйте записать еще раз.",
                "The video could not be saved correctly. Try recording again."
            )
        }
    }
}

@MainActor
final class ScreenRecorder: NSObject, @unchecked Sendable, SCStreamDelegate, SCRecordingOutputDelegate {
    private struct SessionParameters {
        let audioMode: AudioCaptureMode
        let separateMicrophone: Bool
        let microphoneDeviceID: String?
        let targetBitrateKbps: Int
        let fileFormat: VideoFileFormat
        let codec: VideoCodecOption
        let frameRate: VideoFrameRateOption
        let showCursor: Bool
    }

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var recordingDidStart = false
    private var recordingCompletion: Result<Void, Error>?
    private var audioCapture: RecordingAudioCapture?
    private var activeSegmentURL: URL?
    private var finalOutputURL: URL?
    private var sessionParameters: SessionParameters?
    private var segmentURLs: [URL] = []
    private var segmentAudio: [URL: CapturedRecordingAudio] = [:]
    private var temporaryAudioDirectories: [URL] = []
    private var state: ScreenRecordingState = .idle
    private var isStarting = false
    private var isStopping = false
    private var ignoreStreamStopCallback = false

    var onRecordingStateChanged: ((ScreenRecordingState) -> Void)?
    var onRecordingFailed: ((Error) -> Void)?
    private(set) var isPreparingMicrophone = false
    private(set) var audioWarning: String?

    override init() {}

    var recordingState: ScreenRecordingState {
        state
    }

    var isRecording: Bool {
        state != .idle
    }

    var isPaused: Bool {
        state == .paused
    }

    var isStopInProgress: Bool {
        isStopping || isStarting
    }

    func startRecording(
        audioMode: AudioCaptureMode,
        separateMicrophone: Bool,
        targetBitrateKbps: Int,
        outputDirectory: URL,
        fileFormat: VideoFileFormat,
        codec: VideoCodecOption,
        frameRate: VideoFrameRateOption,
        showCursor: Bool
    ) async throws -> URL {
        if state != .idle || isStopping || isStarting {
            throw ScreenRecorderError.alreadyRecording
        }
        isStarting = true
        defer { isStarting = false }
        audioWarning = nil

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        guard ensureScreenRecordingPermission() else {
            throw ScreenRecorderError.permissionDenied
        }

        var microphoneDeviceID: String?
        if audioMode.capturesMicrophone {
            let authorization = AVCaptureDevice.authorizationStatus(for: .audio)
            let allowed = authorization == .notDetermined
                ? await AVCaptureDevice.requestAccess(for: .audio)
                : authorization == .authorized
            guard allowed else { throw ScreenRecorderError.microphonePermissionDenied }
            let device = AVCaptureDevice.default(for: .audio)
            microphoneDeviceID = device?.uniqueID
            Logger(subsystem: "com.maksim.cliptara", category: "RecordingAudio")
                .info("Selected microphone: \(device?.localizedName ?? "System default", privacy: .public)")
        }

        let finalURL = makeFinalOutputURL(directory: outputDirectory, format: fileFormat)

        finalOutputURL = finalURL
        sessionParameters = SessionParameters(
            audioMode: audioMode,
            separateMicrophone: separateMicrophone && audioMode.capturesMicrophone,
            microphoneDeviceID: microphoneDeviceID,
            targetBitrateKbps: clampBitrate(targetBitrateKbps),
            fileFormat: fileFormat,
            codec: codec,
            frameRate: frameRate,
            showCursor: showCursor
        )
        segmentURLs.removeAll()

        guard let parameters = sessionParameters else {
            throw ScreenRecorderError.streamSetupFailed
        }

        do {
            try await beginSegmentCapture(parameters: parameters)
        } catch {
            clearSession(removeTemporaryFiles: true)
            throw error
        }
        state = .recording
        notifyRecordingStateChange(.recording)

        return finalURL
    }

    func pauseRecording() async throws {
        guard state == .recording else {
            throw ScreenRecorderError.notRecording
        }

        if isStopping {
            throw ScreenRecorderError.stopInProgress
        }

        isStopping = true
        defer { isStopping = false }
        do {
            try await finalizeCurrentSegmentAndStopCapture()
            state = .paused
            notifyRecordingStateChange(.paused)
        } catch {
            clearSession(removeTemporaryFiles: true)
            notifyRecordingStateChange(.idle)
            throw error
        }
    }

    func resumeRecording() async throws {
        guard state == .paused else {
            throw ScreenRecorderError.notPaused
        }

        if isStopping || isStarting {
            throw ScreenRecorderError.stopInProgress
        }

        guard let parameters = sessionParameters else {
            throw ScreenRecorderError.streamSetupFailed
        }

        isStarting = true
        defer { isStarting = false }
        try await beginSegmentCapture(parameters: parameters)
        state = .recording
        notifyRecordingStateChange(.recording)
    }

    func stopRecording() async throws -> URL {
        guard state != .idle else {
            throw ScreenRecorderError.notRecording
        }
        if isStopping {
            throw ScreenRecorderError.stopInProgress
        }

        isStopping = true
        defer {
            isStopping = false
        }

        let wasRecording = state == .recording
        if wasRecording {
            do {
                try await finalizeCurrentSegmentAndStopCapture()
            } catch {
                clearSession(removeTemporaryFiles: true)
                notifyRecordingStateChange(.idle)
                throw error
            }
        }

        guard let finalOutputURL,
              let parameters = sessionParameters else {
            clearSession(removeTemporaryFiles: true)
            notifyRecordingStateChange(.idle)
            throw ScreenRecorderError.invalidOutputFile
        }

        guard !segmentURLs.isEmpty else {
            clearSession(removeTemporaryFiles: true)
            notifyRecordingStateChange(.idle)
            throw ScreenRecorderError.invalidOutputFile
        }

        do {
            if parameters.audioMode.capturesMicrophone {
                audioWarning = try await RecordingAudioExport.save(
                    segments: segmentURLs,
                    audio: segmentAudio,
                    to: finalOutputURL,
                    format: parameters.fileFormat,
                    separateMicrophone: parameters.separateMicrophone
                )
            } else {
                try await produceFinalOutput(from: segmentURLs, to: finalOutputURL, format: parameters.fileFormat)
            }
            cleanupTemporarySegments()
            clearSession(removeTemporaryFiles: false)
            notifyRecordingStateChange(.idle)
            return finalOutputURL
        } catch {
            clearSession(removeTemporaryFiles: true)
            notifyRecordingStateChange(.idle)
            throw error
        }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard let output = self.recordingOutput, ObjectIdentifier(output) == id else { return }
            self.recordingDidStart = true
        }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard let output = self.recordingOutput, ObjectIdentifier(output) == id else { return }
            self.recordingCompletion = .success(())
        }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let id = ObjectIdentifier(recordingOutput)
        Task { @MainActor in
            guard let output = self.recordingOutput, ObjectIdentifier(output) == id else { return }
            self.recordingCompletion = .failure(error)
            guard !self.isStopInProgress else { return }
            self.clearSession(removeTemporaryFiles: true)
            self.notifyRecordingStateChange(.idle)
            self.onRecordingFailed?(error)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stoppedID = ObjectIdentifier(stream)
        Task { @MainActor in
            guard !self.ignoreStreamStopCallback else {
                return
            }
            if let current = self.stream, ObjectIdentifier(current) == stoppedID {
                if self.isStarting {
                    self.recordingCompletion = .failure(error)
                    return
                }
                self.clearSession(removeTemporaryFiles: true)
                self.notifyRecordingStateChange(.idle)
                self.onRecordingFailed?(error)
            }
        }
    }

    private func beginSegmentCapture(parameters: SessionParameters) async throws {
        let (filter, configuration, preferredCodec) = try await makeStreamSetup(parameters: parameters)
        let segmentURL = makeSegmentOutputURL(format: parameters.fileFormat)

        if FileManager.default.fileExists(atPath: segmentURL.path) {
            try? FileManager.default.removeItem(at: segmentURL)
        }

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = segmentURL

        if recordingConfiguration.availableOutputFileTypes.contains(parameters.fileFormat.fileType) {
            recordingConfiguration.outputFileType = parameters.fileFormat.fileType
        } else if recordingConfiguration.availableOutputFileTypes.contains(.mov) {
            recordingConfiguration.outputFileType = .mov
        } else if let fallbackType = recordingConfiguration.availableOutputFileTypes.first {
            recordingConfiguration.outputFileType = fallbackType
        }

        if recordingConfiguration.availableVideoCodecTypes.contains(preferredCodec) {
            recordingConfiguration.videoCodecType = preferredCodec
        } else if recordingConfiguration.availableVideoCodecTypes.contains(.h264) {
            recordingConfiguration.videoCodecType = .h264
        } else if let fallbackCodec = recordingConfiguration.availableVideoCodecTypes.first {
            recordingConfiguration.videoCodecType = fallbackCodec
        }

        let recordingOutput = SCRecordingOutput(configuration: recordingConfiguration, delegate: self)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let capture = parameters.audioMode.capturesMicrophone
            ? try RecordingAudioCapture(captureSystemAudio: parameters.audioMode.capturesSystemAudio)
            : nil
        self.recordingOutput = recordingOutput
        self.stream = stream
        recordingCompletion = nil
        recordingDidStart = false

        var streamStarted = false
        var outputAttached = false
        do {
            if let capture {
                isPreparingMicrophone = true
                notifyRecordingStateChange(state)
                defer {
                    isPreparingMicrophone = false
                    notifyRecordingStateChange(state)
                }
                try capture.attach(to: stream)
                try await stream.startCapture()
                streamStarted = true
                try await capture.waitForMicrophone(timeout: .seconds(3))
                if let recordingCompletion { try recordingCompletion.get() }
                let startTime = stream.synchronizationClock.map(CMClockGetTime)
                capture.armRecording(at: startTime?.isNumeric == true ? startTime : nil)
                try stream.addRecordingOutput(recordingOutput)
                outputAttached = true
                try await waitForRecordingStart()
            } else {
                try stream.addRecordingOutput(recordingOutput)
                outputAttached = true
                try await stream.startCapture()
                streamStarted = true
            }
            if let recordingCompletion { try recordingCompletion.get() }
        } catch {
            if outputAttached { try? stream.removeRecordingOutput(recordingOutput) }
            if streamStarted { try? await stream.stopCapture() }
            if let capture {
                _ = await capture.finish()
                try? FileManager.default.removeItem(at: capture.directory)
            }
            try? FileManager.default.removeItem(at: segmentURL)
            clearStreamOnly()
            throw error
        }

        self.activeSegmentURL = segmentURL
        audioCapture = capture
        if let capture { temporaryAudioDirectories.append(capture.directory) }
    }

    private func finalizeCurrentSegmentAndStopCapture() async throws {
        guard let activeStream = stream,
              let segmentURL = activeSegmentURL else {
            throw ScreenRecorderError.streamSetupFailed
        }

        ignoreStreamStopCallback = true
        defer {
            ignoreStreamStopCallback = false
        }

        try await activeStream.stopCapture()
        if let audioCapture {
            segmentAudio[segmentURL] = await audioCapture.finish()
        }
        try await waitForRecordingCompletion()
        guard await isVideoFileReady(at: segmentURL) else { throw ScreenRecorderError.invalidOutputFile }
        segmentURLs.append(segmentURL)
        clearStreamOnly()
    }

    private func produceFinalOutput(from segments: [URL], to outputURL: URL, format: VideoFileFormat) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        if segments.count == 1, let segment = segments.first, format == .mov {
            do {
                try FileManager.default.moveItem(at: segment, to: outputURL)
            } catch {
                try FileManager.default.copyItem(at: segment, to: outputURL)
            }
            let ready = await isVideoFileReady(at: outputURL)
            if ready {
                return
            }
            throw ScreenRecorderError.invalidOutputFile
        }

        try await mergeSegments(segments, outputURL: outputURL, fileType: format.fileType)
    }

    private func mergeSegments(_ segments: [URL], outputURL: URL, fileType: AVFileType) async throws {
        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ScreenRecorderError.invalidOutputFile
        }

        let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var insertTime = CMTime.zero
        var didInsertVideo = false

        for segmentURL in segments {
            let asset = AVURLAsset(url: segmentURL)

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let videoTrack = videoTracks.first else {
                continue
            }

            let duration = try await asset.load(.duration)
            if duration <= .zero {
                continue
            }

            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: insertTime)

            if !didInsertVideo {
                let transform = try await videoTrack.load(.preferredTransform)
                compositionVideoTrack.preferredTransform = transform
                didInsertVideo = true
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let audioTrack = audioTracks.first, let compositionAudioTrack {
                try? compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: insertTime)
            }

            insertTime = CMTimeAdd(insertTime, duration)
        }

        guard didInsertVideo else {
            throw ScreenRecorderError.invalidOutputFile
        }

        try await exportComposition(composition, outputURL: outputURL, fileType: fileType)
    }

    private func exportComposition(_ composition: AVMutableComposition, outputURL: URL, fileType: AVFileType) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let presetCandidates = [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality]
        var lastError: Error?

        for preset in presetCandidates {
            guard let exportSession = AVAssetExportSession(asset: composition, presetName: preset) else {
                continue
            }

            try? FileManager.default.removeItem(at: outputURL)
            exportSession.outputURL = outputURL
            exportSession.shouldOptimizeForNetworkUse = false
            exportSession.outputFileType = exportSession.supportedFileTypes.contains(fileType) ? fileType : .mov

            do {
                try await runExport(exportSession: exportSession, outputURL: outputURL, outputFileType: exportSession.outputFileType ?? .mov)
                let ready = await isVideoFileReady(at: outputURL)
                if ready {
                    return
                }
                throw ScreenRecorderError.invalidOutputFile
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ScreenRecorderError.invalidOutputFile
    }

    private func runExport(exportSession: AVAssetExportSession, outputURL: URL, outputFileType: AVFileType) async throws {
        try await exportSession.export(to: outputURL, as: outputFileType)
    }

    private func cleanupTemporarySegments() {
        for url in segmentURLs {
            try? FileManager.default.removeItem(at: url)
        }
        segmentURLs.removeAll()
        for directory in temporaryAudioDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryAudioDirectories.removeAll()
        segmentAudio.removeAll()
    }

    private func clearSession(removeTemporaryFiles: Bool) {
        let unfinishedURL = activeSegmentURL
        clearStreamOnly()
        if removeTemporaryFiles {
            cleanupTemporarySegments()
            if let unfinishedURL {
                try? FileManager.default.removeItem(at: unfinishedURL)
            }
            if let finalOutputURL {
                try? FileManager.default.removeItem(at: finalOutputURL)
            }
        } else {
            segmentURLs.removeAll()
        }
        activeSegmentURL = nil
        finalOutputURL = nil
        sessionParameters = nil
        state = .idle
    }

    private func clearStreamOnly() {
        stream = nil
        recordingOutput = nil
        recordingDidStart = false
        recordingCompletion = nil
        audioCapture = nil
        activeSegmentURL = nil
    }

    private func waitForRecordingCompletion() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(6)
        while recordingCompletion == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        guard let recordingCompletion else { throw ScreenRecorderError.invalidOutputFile }
        try recordingCompletion.get()
    }

    private func waitForRecordingStart() async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(6)
        while !recordingDidStart, clock.now < deadline {
            if let recordingCompletion { try recordingCompletion.get() }
            try await Task.sleep(for: .milliseconds(25))
        }
        guard recordingDidStart else { throw ScreenRecorderError.streamSetupFailed }
    }

    private func notifyRecordingStateChange(_ state: ScreenRecordingState) {
        onRecordingStateChanged?(state)
    }

    private func makeStreamSetup(
        parameters: SessionParameters
    ) async throws -> (SCContentFilter, SCStreamConfiguration, AVVideoCodecType) {
        let shareableContent = try await SCShareableContent.current

        guard let display = chooseDisplay(from: shareableContent.displays) else {
            throw ScreenRecorderError.displayNotFound
        }

        let contentFilter = SCContentFilter(display: display, excludingWindows: [])
        let captureProfile = makeCaptureProfile(
            nativeWidth: Int(CGDisplayPixelsWide(display.displayID)),
            nativeHeight: Int(CGDisplayPixelsHigh(display.displayID)),
            targetBitrateKbps: parameters.targetBitrateKbps
        )

        let streamConfig = SCStreamConfiguration()
        streamConfig.width = captureProfile.width
        streamConfig.height = captureProfile.height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(parameters.frameRate.fps))
        streamConfig.showsCursor = parameters.showCursor
        streamConfig.capturesAudio = parameters.audioMode.capturesSystemAudio
        streamConfig.excludesCurrentProcessAudio = false
        streamConfig.sampleRate = 48_000
        streamConfig.channelCount = 2

        streamConfig.captureMicrophone = parameters.audioMode.capturesMicrophone
        streamConfig.microphoneCaptureDeviceID = parameters.microphoneDeviceID

        return (contentFilter, streamConfig, parameters.codec.codecType)
    }

    private func chooseDisplay(from displays: [SCDisplay]) -> SCDisplay? {
        let mainID = CGMainDisplayID()
        return displays.first(where: { $0.displayID == mainID }) ?? displays.first
    }

    private func ensureScreenRecordingPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        return CGRequestScreenCaptureAccess()
    }

    private func makeFinalOutputURL(directory: URL, format: VideoFileFormat) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let basename = "CliptaraVid_\(formatter.string(from: Date()))"
        let url = directory.appendingPathComponent(basename).appendingPathExtension(format.fileExtension)
        let sidecar = RecordingAudioExport.microphoneURL(for: url)
        if FileManager.default.fileExists(atPath: url.path) || FileManager.default.fileExists(atPath: sidecar.path) {
            return directory.appendingPathComponent("\(basename)_\(UUID().uuidString.prefix(8))")
                .appendingPathExtension(format.fileExtension)
        }
        return url
    }

    private func makeSegmentOutputURL(format: VideoFileFormat) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("cliptara-segment-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)
    }

    private func isVideoFileReady(at url: URL) async -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else {
            return false
        }

        let asset = AVURLAsset(url: url)

        do {
            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard !videoTracks.isEmpty else {
                return false
            }

            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite && seconds >= 0
        } catch {
            return false
        }
    }

    private func makeCaptureProfile(
        nativeWidth: Int,
        nativeHeight: Int,
        targetBitrateKbps: Int
    ) -> CaptureProfile {
        let bitrate = clampBitrate(targetBitrateKbps)

        let baselineBitrateKbps = 12_000.0
        let ratio = min(max(Double(bitrate) / baselineBitrateKbps, 0.14), 1.0)
        let scale = sqrt(ratio)

        let minWidth = min(640, nativeWidth)
        let minHeight = min(360, nativeHeight)

        var width = Int((Double(nativeWidth) * scale).rounded(.down))
        var height = Int((Double(nativeHeight) * scale).rounded(.down))

        width = makeEven(max(minWidth, min(nativeWidth, width)))
        height = makeEven(max(minHeight, min(nativeHeight, height)))

        return CaptureProfile(width: width, height: height)
    }

    private func clampBitrate(_ value: Int) -> Int {
        min(max(value, 800), 50_000)
    }

    private func makeEven(_ value: Int) -> Int {
        if value <= 2 {
            return 2
        }
        return value.isMultiple(of: 2) ? value : (value - 1)
    }
}

private struct CaptureProfile {
    let width: Int
    let height: Int
}
