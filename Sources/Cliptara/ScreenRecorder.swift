import AVFoundation
import CoreGraphics
import Foundation
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
        let targetBitrateKbps: Int
        let fileFormat: VideoFileFormat
        let codec: VideoCodecOption
        let frameRate: VideoFrameRateOption
        let showCursor: Bool
    }

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var activeSegmentURL: URL?
    private var finalOutputURL: URL?
    private var sessionParameters: SessionParameters?
    private var segmentURLs: [URL] = []
    private var state: ScreenRecordingState = .idle
    private var isStopping = false
    private var ignoreStreamStopCallback = false

    var onRecordingStateChanged: ((ScreenRecordingState) -> Void)?

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
        isStopping
    }

    func startRecording(
        audioMode: AudioCaptureMode,
        targetBitrateKbps: Int,
        outputDirectory: URL,
        fileFormat: VideoFileFormat,
        codec: VideoCodecOption,
        frameRate: VideoFrameRateOption,
        showCursor: Bool
    ) async throws -> URL {
        if state != .idle || isStopping {
            throw ScreenRecorderError.alreadyRecording
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        guard ensureScreenRecordingPermission() else {
            throw ScreenRecorderError.permissionDenied
        }

        let finalURL = makeFinalOutputURL(directory: outputDirectory, format: fileFormat)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try? FileManager.default.removeItem(at: finalURL)
        }

        finalOutputURL = finalURL
        sessionParameters = SessionParameters(
            audioMode: audioMode,
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

        _ = try await beginSegmentCapture(parameters: parameters)
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

        try await finalizeCurrentSegmentAndStopCapture()
        state = .paused
        notifyRecordingStateChange(.paused)
    }

    func resumeRecording() async throws {
        guard state == .paused else {
            throw ScreenRecorderError.notPaused
        }

        if isStopping {
            throw ScreenRecorderError.stopInProgress
        }

        guard let parameters = sessionParameters else {
            throw ScreenRecorderError.streamSetupFailed
        }

        _ = try await beginSegmentCapture(parameters: parameters)
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
            try await produceFinalOutput(
                from: segmentURLs,
                to: finalOutputURL,
                format: parameters.fileFormat
            )
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

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {}

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            self.clearSession(removeTemporaryFiles: true)
            self.notifyRecordingStateChange(.idle)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stoppedID = ObjectIdentifier(stream)
        Task { @MainActor in
            guard !self.ignoreStreamStopCallback else {
                return
            }
            if let current = self.stream, ObjectIdentifier(current) == stoppedID {
                self.clearSession(removeTemporaryFiles: true)
                self.notifyRecordingStateChange(.idle)
            }
        }
    }

    private func beginSegmentCapture(parameters: SessionParameters) async throws -> URL {
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

        do {
            try stream.addRecordingOutput(recordingOutput)
            try await stream.startCapture()
        } catch {
            try? stream.removeRecordingOutput(recordingOutput)
            throw ScreenRecorderError.streamSetupFailed
        }

        self.stream = stream
        self.recordingOutput = recordingOutput
        self.activeSegmentURL = segmentURL

        return segmentURL
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

        do {
            try await activeStream.stopCapture()
        } catch {
            clearStreamOnly()
            throw ScreenRecorderError.streamSetupFailed
        }

        if let output = recordingOutput {
            try? activeStream.removeRecordingOutput(output)
        }

        let ready = await waitForFinalizedVideo(at: segmentURL, timeout: 6.0)
        clearStreamOnly()

        if ready || FileManager.default.fileExists(atPath: segmentURL.path) {
            segmentURLs.append(segmentURL)
            activeSegmentURL = nil
            return
        }
        throw ScreenRecorderError.invalidOutputFile
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
    }

    private func clearSession(removeTemporaryFiles: Bool) {
        clearStreamOnly()
        if removeTemporaryFiles {
            cleanupTemporarySegments()
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
        activeSegmentURL = nil
    }

    private func waitForFinalizedVideo(at url: URL, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await isVideoFileReady(at: url) {
                return true
            }
            try? await Task.sleep(nanoseconds: 140_000_000)
        }
        return await isVideoFileReady(at: url)
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

        if #available(macOS 15.0, *) {
            streamConfig.captureMicrophone = false
        }

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
        let fileName = "CliptaraVid_\(formatter.string(from: Date())).\(format.fileExtension)"
        return directory.appendingPathComponent(fileName)
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
