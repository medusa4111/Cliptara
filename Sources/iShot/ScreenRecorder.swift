import AVFoundation
import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

enum ScreenRecorderError: LocalizedError, Equatable {
    case alreadyRecording
    case stopInProgress
    case notRecording
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
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var activeOutputURL: URL?
    private var isStopping = false

    var onRecordingStateChanged: ((Bool) -> Void)?

    override init() {}

    var isRecording: Bool {
        stream != nil && activeOutputURL != nil
    }

    var isStopInProgress: Bool {
        isStopping
    }

    func startRecording(audioMode: AudioCaptureMode, outputDirectory: URL) async throws -> URL {
        if stream != nil || isStopping {
            throw ScreenRecorderError.alreadyRecording
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        guard ensureScreenRecordingPermission() else {
            throw ScreenRecorderError.permissionDenied
        }

        let (filter, configuration) = try await makeStreamSetup(audioMode: audioMode)
        let outputURL = makeOutputURL(directory: outputDirectory)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        if recordingConfiguration.availableOutputFileTypes.contains(.mov) {
            recordingConfiguration.outputFileType = .mov
        }
        if recordingConfiguration.availableVideoCodecTypes.contains(.h264) {
            recordingConfiguration.videoCodecType = .h264
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
        self.activeOutputURL = outputURL
        self.isStopping = false
        notifyRecordingStateChange(isRecording: true)

        return outputURL
    }

    func stopRecording() async throws -> URL {
        guard let activeStream = stream,
              let outputURL = activeOutputURL else {
            throw ScreenRecorderError.notRecording
        }
        if isStopping {
            throw ScreenRecorderError.stopInProgress
        }

        isStopping = true
        defer {
            isStopping = false
        }

        do {
            try await activeStream.stopCapture()
        } catch {
            // Если stop неуспешен, принудительно выходим из режима записи в UI.
            clearState()
            notifyRecordingStateChange(isRecording: false)
            throw error
        }

        if let output = recordingOutput {
            try? activeStream.removeRecordingOutput(output)
        }

        let ready = await waitForFinalizedVideo(at: outputURL, timeout: 6.0)

        clearState()
        notifyRecordingStateChange(isRecording: false)

        if ready || FileManager.default.fileExists(atPath: outputURL.path) {
            return outputURL
        }
        throw ScreenRecorderError.invalidOutputFile
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {}

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {}

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in
            self.clearState()
            self.notifyRecordingStateChange(isRecording: false)
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stoppedID = ObjectIdentifier(stream)
        Task { @MainActor in
            if let current = self.stream, ObjectIdentifier(current) == stoppedID {
                self.clearState()
                self.notifyRecordingStateChange(isRecording: false)
            }
        }
    }

    private func clearState() {
        stream = nil
        recordingOutput = nil
        activeOutputURL = nil
    }

    private func waitForFinalizedVideo(at url: URL, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isVideoFileReady(at: url) {
                return true
            }
            try? await Task.sleep(nanoseconds: 140_000_000)
        }
        return isVideoFileReady(at: url)
    }

    private func notifyRecordingStateChange(isRecording: Bool) {
        onRecordingStateChanged?(isRecording)
    }

    private func makeStreamSetup(audioMode: AudioCaptureMode) async throws -> (SCContentFilter, SCStreamConfiguration) {
        let shareableContent = try await SCShareableContent.current

        guard let display = chooseDisplay(from: shareableContent.displays) else {
            throw ScreenRecorderError.displayNotFound
        }

        let contentFilter = SCContentFilter(display: display, excludingWindows: [])

        let streamConfig = SCStreamConfiguration()
        streamConfig.width = CGDisplayPixelsWide(display.displayID)
        streamConfig.height = CGDisplayPixelsHigh(display.displayID)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfig.showsCursor = true
        streamConfig.capturesAudio = audioMode.capturesSystemAudio
        streamConfig.excludesCurrentProcessAudio = false
        streamConfig.sampleRate = 48_000
        streamConfig.channelCount = 2

        if #available(macOS 15.0, *) {
            streamConfig.captureMicrophone = false
        }

        return (contentFilter, streamConfig)
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

    private func makeOutputURL(directory: URL) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "CliptaraVid_\(formatter.string(from: Date())).mov"
        return directory.appendingPathComponent(name)
    }

    private func isVideoFileReady(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard fileSize > 0 else {
            return false
        }

        let asset = AVURLAsset(url: url)
        let videoTracks = asset.tracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            return false
        }

        let duration = CMTimeGetSeconds(asset.duration)
        return duration.isFinite && duration >= 0
    }
}
