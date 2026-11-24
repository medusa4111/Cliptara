import AVFoundation
import Foundation
import OSLog

@MainActor
enum RecordingAudioExport {
    static func microphoneURL(for video: URL) -> URL {
        video.deletingLastPathComponent().appendingPathComponent(
            video.deletingPathExtension().lastPathComponent + "_mic.m4a"
        )
    }

    static func save(
        segments: [URL],
        audio: [URL: CapturedRecordingAudio],
        to output: URL,
        format: VideoFileFormat,
        separateMicrophone: Bool
    ) async throws -> String? {
        let files = FileManager.default
        let staging = files.temporaryDirectory.appendingPathComponent("cliptara-export-\(UUID().uuidString)")
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }

        let video = AVMutableComposition()
        let videoTrack = try addTrack(.video, to: video)
        let sound = AVMutableComposition()
        let systemTrack = try addTrack(.audio, to: sound)
        let microphone = separateMicrophone ? AVMutableComposition() : sound
        let microphoneTrack = try addTrack(.audio, to: microphone)

        var time = CMTime.zero
        var noMicrophone = false
        var microphonePeak: Float = 0
        var audioProblem = false
        for segment in segments {
            let asset = AVURLAsset(url: segment)
            guard let source = try await asset.loadTracks(withMediaType: .video).first else {
                throw ScreenRecorderError.invalidOutputFile
            }
            let videoRange = try await source.load(.timeRange)
            guard videoRange.duration.isNumeric, videoRange.duration > .zero else {
                throw ScreenRecorderError.invalidOutputFile
            }
            if time == .zero { videoTrack.preferredTransform = try await source.load(.preferredTransform) }
            try videoTrack.insertTimeRange(videoRange, of: source, at: time)

            let captured = audio[segment]
            microphonePeak = max(microphonePeak, captured?.microphonePeak ?? 0)
            if let system = captured?.system {
                do { _ = try await insert(system, in: systemTrack, at: time, videoDuration: videoRange.duration) }
                catch { audioProblem = true; log(error) }
            }
            if let mic = captured?.microphone {
                do {
                    if try await !insert(mic, in: microphoneTrack, at: time, videoDuration: videoRange.duration) {
                        noMicrophone = true
                    }
                } catch { noMicrophone = true; log(error) }
            } else {
                noMicrophone = true
            }
            audioProblem = audioProblem || !(captured?.failures.isEmpty ?? true)
            time = CMTimeAdd(time, videoRange.duration)
        }
        guard time > .zero else { throw ScreenRecorderError.invalidOutputFile }

        // Materialize one mixed audio track so players hear both sources.
        var hasSoundtrack = false
        if hasAudio(systemTrack) || (!separateMicrophone && hasAudio(microphoneTrack)) {
            let soundtrack = staging.appendingPathComponent("soundtrack.m4a")
            let tracks = separateMicrophone ? [systemTrack] : [systemTrack, microphoneTrack]
            do {
                try await renderAudio(sound, tracks: tracks, duration: time, to: soundtrack)
                let mixed = CapturedRecordingAudio.Track(url: soundtrack, offset: .zero)
                let target = try addTrack(.audio, to: video)
                do {
                    hasSoundtrack = try await insert(mixed, in: target, at: .zero, videoDuration: time)
                } catch {
                    video.removeTrack(target)
                    throw error
                }
                if !hasSoundtrack {
                    video.removeTrack(target)
                    audioProblem = true
                }
            } catch {
                audioProblem = true
                log(error)
            }
        }

        let stagedVideo = staging.appendingPathComponent("recording").appendingPathExtension(format.fileExtension)
        do {
            try await export(video, preset: AVAssetExportPresetPassthrough, to: stagedVideo, as: format.fileType)
        } catch {
            try? files.removeItem(at: stagedVideo)
            try await export(video, preset: AVAssetExportPresetHighestQuality, to: stagedVideo, as: format.fileType)
        }
        let finalized = AVURLAsset(url: stagedVideo)
        guard try await !finalized.loadTracks(withMediaType: .video).isEmpty else {
            throw ScreenRecorderError.invalidOutputFile
        }
        if hasSoundtrack, try await finalized.loadTracks(withMediaType: .audio).isEmpty {
            throw ScreenRecorderError.invalidOutputFile
        }
        try files.moveItem(at: stagedVideo, to: output)

        if separateMicrophone, hasAudio(microphoneTrack) {
            let stagedMic = staging.appendingPathComponent("voice.m4a")
            do {
                try await renderAudio(microphone, tracks: [microphoneTrack], duration: time, to: stagedMic)
                try files.moveItem(at: stagedMic, to: microphoneURL(for: output))
            } catch {
                log(error)
                return Localizer.text(
                    "Видео сохранено, но не удалось сохранить отдельный файл микрофона.",
                    "The video was saved, but the separate microphone file could not be saved."
                )
            }
        }

        if noMicrophone {
            return Localizer.text(
                "Видео сохранено, но часть записи или вся запись осталась без микрофона.",
                "The video was saved, but microphone audio is missing from part or all of the recording."
            )
        }
        if audioProblem {
            return Localizer.text(
                "Видео сохранено, но при записи звука возникли ошибки. Проверьте дорожки.",
                "The video was saved, but there were audio capture errors. Check the audio tracks."
            )
        }
        if microphonePeak < 0.001 {
            return Localizer.text(
                "Видео сохранено. Сигнал микрофона был очень тихим. Проверьте устройство ввода macOS.",
                "The video was saved. The microphone signal was very quiet. Check the macOS input device."
            )
        }
        return nil
    }

    private static func insert(
        _ captured: CapturedRecordingAudio.Track,
        in target: AVMutableCompositionTrack,
        at time: CMTime,
        videoDuration: CMTime
    ) async throws -> Bool {
        let asset = AVURLAsset(url: captured.url)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ScreenRecorderError.invalidOutputFile
        }
        let range = try await source.load(.timeRange)
        let trim = CMTimeMaximum(.zero, .zero - captured.offset)
        let delay = CMTimeMaximum(.zero, captured.offset)
        let duration = CMTimeMinimum(range.duration - trim, videoDuration - delay)
        guard duration.isNumeric, duration > .zero else { return false }
        try target.insertTimeRange(
            CMTimeRange(start: range.start + trim, duration: duration), of: source, at: time + delay
        )
        return true
    }

    private static func renderAudio(
        _ composition: AVMutableComposition,
        tracks: [AVMutableCompositionTrack],
        duration: CMTime,
        to url: URL
    ) async throws {
        let active = tracks.filter { hasAudio($0) }
        let mix = AVMutableAudioMix()
        mix.inputParameters = active.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(active.count > 1 ? 0.5 : 1, at: .zero)
            return parameters
        }
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ScreenRecorderError.invalidOutputFile
        }
        exporter.audioMix = mix
        let compositionDuration = try await composition.load(.duration)
        exporter.timeRange = CMTimeRange(start: .zero, duration: CMTimeMinimum(duration, compositionDuration))
        try await exporter.export(to: url, as: .m4a)
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else {
            throw ScreenRecorderError.invalidOutputFile
        }
    }

    private static func hasAudio(_ track: AVCompositionTrack) -> Bool {
        track.segments.contains { !$0.isEmpty }
    }

    private static func addTrack(_ mediaType: AVMediaType, to composition: AVMutableComposition) throws -> AVMutableCompositionTrack {
        guard let track = composition.addMutableTrack(withMediaType: mediaType, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ScreenRecorderError.invalidOutputFile
        }
        return track
    }

    private static func export(_ asset: AVAsset, preset: String, to url: URL, as fileType: AVFileType) async throws {
        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset),
              exporter.supportedFileTypes.contains(fileType) else { throw ScreenRecorderError.invalidOutputFile }
        try await exporter.export(to: url, as: fileType)
    }

    private static func log(_ error: Error) {
        Logger(subsystem: "com.maksim.cliptara", category: "RecordingAudio")
            .error("Audio export: \(error.localizedDescription, privacy: .public)")
    }
}
