import AVFoundation
import Foundation

struct VideoCompressionResult {
    let outputURL: URL
    let originalSizeBytes: Int64
    let outputSizeBytes: Int64
    let targetSizeBytes: Int64

    var metTarget: Bool {
        outputSizeBytes <= targetSizeBytes
    }
}

enum VideoCompressorError: LocalizedError {
    case inputFileNotFound
    case inputHasNoVideoTrack
    case invalidTargetSize
    case destinationUnavailable
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .inputFileNotFound:
            return Localizer.text("Исходный видеофайл не найден.", "Input video file was not found.")
        case .inputHasNoVideoTrack:
            return Localizer.text("Выбранный файл не содержит видеодорожку.", "The selected file does not contain a video track.")
        case .invalidTargetSize:
            return Localizer.text("Укажите корректный целевой размер в МБ.", "Enter a valid target size in MB.")
        case .destinationUnavailable:
            return Localizer.text("Не удалось подготовить папку назначения.", "Could not prepare output destination folder.")
        case .compressionFailed:
            return Localizer.text("Не удалось сжать видео.", "Could not compress the video.")
        }
    }
}

final class VideoCompressor: @unchecked Sendable {
    func compress(
        inputURL: URL,
        targetSizeMB: Int,
        destinationDirectory: URL
    ) async throws -> VideoCompressionResult {
        guard targetSizeMB > 0 else {
            throw VideoCompressorError.invalidTargetSize
        }
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw VideoCompressorError.inputFileNotFound
        }
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw VideoCompressorError.destinationUnavailable
        }

        let originalSize = fileSize(for: inputURL)
        let targetBytes = Int64(targetSizeMB) * 1_048_576

        let asset = AVURLAsset(url: inputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard !videoTracks.isEmpty else {
            throw VideoCompressorError.inputHasNoVideoTrack
        }

        let compatiblePresets = Set(AVAssetExportSession.exportPresets(compatibleWith: asset))
        let presetCandidates = [
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPresetHighestQuality,
            AVAssetExportPresetHEVC1920x1080,
            AVAssetExportPreset1920x1080,
            AVAssetExportPreset1280x720,
            AVAssetExportPreset960x540,
            AVAssetExportPreset640x480,
            AVAssetExportPresetMediumQuality,
            AVAssetExportPresetLowQuality
        ].filter { compatiblePresets.contains($0) }

        var bestTemporaryURL: URL?
        var bestOutputFileType: AVFileType?
        var bestSize = Int64.max
        let preferredTypes = preferredOutputTypes(for: inputURL.pathExtension)

        for preset in presetCandidates {
            let attempt = try await runAttempt(
                asset: asset,
                preset: preset,
                preferredFileTypes: preferredTypes,
                targetBytes: targetBytes
            )
            guard let attempt else {
                continue
            }

            let outputSize = fileSize(for: attempt.url)
            if outputSize < bestSize {
                if let bestTemporaryURL {
                    try? FileManager.default.removeItem(at: bestTemporaryURL)
                }
                bestTemporaryURL = attempt.url
                bestOutputFileType = attempt.fileType
                bestSize = outputSize
            } else {
                try? FileManager.default.removeItem(at: attempt.url)
            }

            if outputSize <= targetBytes {
                break
            }
        }

        guard let bestTemporaryURL, let bestOutputFileType else {
            throw VideoCompressorError.compressionFailed
        }

        let outputURL = makeOutputURL(
            destinationDirectory: destinationDirectory,
            sourceURL: inputURL,
            fileType: bestOutputFileType
        )
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try FileManager.default.moveItem(at: bestTemporaryURL, to: outputURL)
        } catch {
            throw VideoCompressorError.compressionFailed
        }

        return VideoCompressionResult(
            outputURL: outputURL,
            originalSizeBytes: originalSize,
            outputSizeBytes: fileSize(for: outputURL),
            targetSizeBytes: targetBytes
        )
    }

    private func runAttempt(
        asset: AVAsset,
        preset: String,
        preferredFileTypes: [AVFileType],
        targetBytes: Int64
    ) async throws -> (url: URL, fileType: AVFileType)? {
        guard let export = AVAssetExportSession(asset: asset, presetName: preset) else {
            return nil
        }

        export.shouldOptimizeForNetworkUse = true
        export.fileLengthLimit = targetBytes

        guard let selectedType = preferredFileTypes.first(where: { export.supportedFileTypes.contains($0) }) else {
            return nil
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cliptara-compress-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension(for: selectedType))
        try? FileManager.default.removeItem(at: tempURL)

        do {
            try await export.export(to: tempURL, as: selectedType)
            return (tempURL, selectedType)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return nil
        }
    }

    private func makeOutputURL(destinationDirectory: URL, sourceURL: URL, fileType: AVFileType) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"

        let sourceName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = fileExtension(for: fileType)
        let outputName = "Compressed_\(sourceName)_\(formatter.string(from: Date())).\(ext)"
        return destinationDirectory.appendingPathComponent(outputName, isDirectory: false)
    }

    private func preferredOutputTypes(for inputExtension: String) -> [AVFileType] {
        switch inputExtension.lowercased() {
        case "mov":
            return [.mov, .mp4]
        case "mp4", "m4v":
            return [.mp4, .mov]
        default:
            return [.mp4, .mov]
        }
    }

    private func fileSize(for url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private func fileExtension(for fileType: AVFileType) -> String {
        switch fileType {
        case .mov:
            return "mov"
        default:
            return "mp4"
        }
    }
}
