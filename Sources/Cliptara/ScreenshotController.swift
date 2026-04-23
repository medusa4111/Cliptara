import Foundation

enum ScreenshotCaptureResult {
    case copiedToClipboard
    case saved(URL)
    case cancelled
}

enum ScreenshotControllerError: LocalizedError {
    case captureFailed(String)

    var errorDescription: String? {
        switch self {
        case .captureFailed(let message):
            return message
        }
    }
}

final class ScreenshotController: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cliptara.screenshot.queue", qos: .userInitiated)

    func captureSelectedArea(
        action: ScreenshotAction,
        format: ScreenshotFileFormat,
        muteSound: Bool,
        directory: URL
    ) async throws -> ScreenshotCaptureResult {
        let build = try prepareArguments(
            action: action,
            format: format,
            interactive: true,
            muteSound: muteSound,
            directory: directory
        )

        let result = try await runScreencapture(arguments: build.arguments)
        if result.status == 0 {
            if let destinationURL = build.destinationURL {
                return .saved(destinationURL)
            }
            return .copiedToClipboard
        }

        let stderr = result.stderr.lowercased()
        if stderr.contains("could not create image from rect") || stderr.contains("user canceled") || stderr.contains("cancel") {
            if let destinationURL = build.destinationURL {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            return .cancelled
        }

        throw ScreenshotControllerError.captureFailed(
            result.stderr.isEmpty
                ? Localizer.text("Не удалось сделать скриншот области.", "Could not capture selected area screenshot.")
                : result.stderr
        )
    }

    func captureFullScreen(
        action: ScreenshotAction,
        format: ScreenshotFileFormat,
        muteSound: Bool,
        directory: URL
    ) async throws -> ScreenshotCaptureResult {
        let build = try prepareArguments(
            action: action,
            format: format,
            interactive: false,
            muteSound: muteSound,
            directory: directory
        )

        let result = try await runScreencapture(arguments: build.arguments)
        guard result.status == 0 else {
            if let destinationURL = build.destinationURL {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            throw ScreenshotControllerError.captureFailed(
                result.stderr.isEmpty
                    ? Localizer.text("Не удалось сделать скриншот экрана.", "Could not capture full-screen screenshot.")
                    : result.stderr
            )
        }

        if let destinationURL = build.destinationURL {
            return .saved(destinationURL)
        }
        return .copiedToClipboard
    }

    private func runScreencapture(arguments: [String]) async throws -> (status: Int32, stderr: String) {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments

                let stderrPipe = Pipe()
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    continuation.resume(returning: (process.terminationStatus, stderr))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func prepareArguments(
        action: ScreenshotAction,
        format: ScreenshotFileFormat,
        interactive: Bool,
        muteSound: Bool,
        directory: URL
    ) throws -> (arguments: [String], destinationURL: URL?) {
        var arguments: [String] = []
        if muteSound {
            arguments.append("-x")
        }
        if interactive {
            arguments.append("-i")
        }

        switch action {
        case .copyToClipboard:
            arguments.append("-c")
            return (arguments, nil)
        case .saveToFiles:
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destinationURL = makeScreenshotURL(directory: directory, format: format)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            arguments += ["-t", format.screencaptureFormat]
            arguments.append(destinationURL.path)
            return (arguments, destinationURL)
        }
    }

    private func makeScreenshotURL(directory: URL, format: ScreenshotFileFormat) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "Screenshot_\(formatter.string(from: Date())).\(format.fileExtension)"
        return directory.appendingPathComponent(filename, isDirectory: false)
    }
}
