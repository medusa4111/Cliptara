@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import ScreenCaptureKit

struct CapturedRecordingAudio {
    struct Track {
        let url: URL
        let offset: CMTime
    }

    let system: Track?
    let microphone: Track?
    let microphonePeak: Float
    let failures: [String]
}

final class RecordingAudioCapture: NSObject, SCStreamOutput, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.maksim.cliptara", category: "RecordingAudio")

    let directory: URL
    private let queue = DispatchQueue(label: "Cliptara.recording.audio")
    private let captureSystemAudio: Bool
    // This state is confined to the sample queue until finish seals it.
    private var sealed = false
    private var recordingArmed = false
    private var audioIsReady = false
    private var recordingStartTime: CMTime?
    private var firstVideoTime: CMTime?
    private var firstMicrophoneTime: CMTime?
    private var firstMicrophoneSignalTime: CMTime?
    private var microphone: AudioFileWriter?
    private var system: AudioFileWriter?
    private var microphonePeak: Float = 0
    private var microphoneFrames = 0
    private var failures: [String] = []

    init(captureSystemAudio: Bool) throws {
        self.captureSystemAudio = captureSystemAudio
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cliptara-audio-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    }

    func attach(to stream: SCStream) throws {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        if captureSystemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
    }

    func waitForMicrophone(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started + timeout
        // Digital silence is common before an input finishes initializing.
        while clock.now < deadline {
            if queue.sync(execute: { audioIsReady }) {
                Self.logger.info("Microphone ready after \(String(describing: started.duration(to: clock.now)))")
                return
            }
            try await Task.sleep(for: .milliseconds(40))
        }
        Self.logger.info("Microphone warmup timed out; starting recording")
    }

    func armRecording(at time: CMTime?) {
        queue.sync {
            recordingStartTime = time
            recordingArmed = true
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        receive(sample, of: type)
    }

    private func receive(_ sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !sealed, sample.isValid, sample.dataReadiness == .ready,
              sample.presentationTimeStamp.isNumeric else { return }
        if !recordingArmed {
            if type == .microphone, !audioIsReady, Self.peak(of: sample) > 0.0001 {
                audioIsReady = true
            }
            return
        }
        switch type {
        case .screen:
            guard firstVideoTime == nil, sample.imageBuffer != nil else { return }
            if let start = recordingStartTime, sample.presentationTimeStamp < start { return }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]]
            if let rawStatus = attachments?.first?[.status] as? Int,
               rawStatus != SCFrameStatus.complete.rawValue { return }
            firstVideoTime = sample.presentationTimeStamp
        case .microphone, .audio:
            guard sample.numSamples > 0 else { return }
            let isMicrophone = type == .microphone
            do {
                if isMicrophone {
                    microphoneFrames += sample.numSamples
                    if firstMicrophoneTime == nil { firstMicrophoneTime = sample.presentationTimeStamp }
                    if microphoneFrames == sample.numSamples, let format = sample.formatDescription,
                       let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                        Self.logger.info("Microphone input: \(asbd.mSampleRate) Hz, \(asbd.mChannelsPerFrame) channel(s)")
                    }
                    let peak = Self.peak(of: sample)
                    microphonePeak = max(microphonePeak, peak)
                    if firstMicrophoneSignalTime == nil, peak > 0.0001 {
                        firstMicrophoneSignalTime = sample.presentationTimeStamp
                    }
                    try append(sample, to: &microphone, named: "microphone")
                } else {
                    try append(sample, to: &system, named: "system")
                }
            } catch {
                let message = "\(isMicrophone ? "Microphone" : "System audio"): \(error.localizedDescription)"
                if !failures.contains(message) { failures.append(message) }
            }
        @unknown default:
            break
        }
    }

    private func append(_ sample: CMSampleBuffer, to track: inout AudioFileWriter?, named name: String) throws {
        if track == nil {
            track = try AudioFileWriter(
                url: directory.appendingPathComponent(name + ".m4a"), firstSample: sample
            )
        }
        try track?.append(sample)
    }

    func finish() async -> CapturedRecordingAudio {
        let snapshot = await withCheckedContinuation { continuation in
            queue.async {
                self.sealed = true
                let videoStart = self.startOfRecording
                if let videoStart, let firstMic = self.firstMicrophoneTime {
                    let offset = (firstMic - videoStart).seconds
                    let signalOffset = self.firstMicrophoneSignalTime.map { ($0 - videoStart).seconds }
                    Self.logger.info("Microphone first packet at \(offset)s; first signal at \(String(describing: signalOffset))s")
                }
                continuation.resume(returning: (
                    self.system, self.microphone, videoStart,
                    self.microphoneFrames, self.microphonePeak, self.failures
                ))
            }
        }
        let (systemWriter, micWriter, videoStart, frames, peak, capturedFailures) = snapshot
        var errors = capturedFailures
        var systemTrack: CapturedRecordingAudio.Track?
        var microphoneTrack: CapturedRecordingAudio.Track?
        do { systemTrack = try await systemWriter?.finish(videoStart: videoStart) }
        catch { errors.append(error.localizedDescription) }
        do { microphoneTrack = try await micWriter?.finish(videoStart: videoStart) }
        catch { errors.append(error.localizedDescription) }
        Self.logger.info("Microphone recorded \(frames) frames, peak \(peak), capture errors \(errors.count)")
        for error in errors { Self.logger.error("\(error, privacy: .public)") }
        return CapturedRecordingAudio(
            system: systemTrack, microphone: microphoneTrack, microphonePeak: peak, failures: errors
        )
    }

    private var startOfRecording: CMTime? {
        guard let anchor = recordingStartTime else { return firstVideoTime }
        if let firstVideoTime, (firstVideoTime - anchor).seconds <= 0.2 { return firstVideoTime }
        return anchor
    }

    private static func peak(of sample: CMSampleBuffer) -> Float {
        guard let description = sample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              asbd.pointee.mFormatID == kAudioFormatLinearPCM else { return 0 }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.numSamples)
        ) else { return 0 }
        buffer.frameLength = buffer.frameCapacity
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(sample.numSamples), into: buffer.mutableAudioBufferList
        ) == noErr else { return 0 }
        var peak: Float = 0
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) {
                let index = frame * buffer.stride
                if let values = buffer.floatChannelData {
                    peak = max(peak, abs(values[channel][index]))
                } else if let values = buffer.int16ChannelData {
                    peak = max(peak, abs(Float(values[channel][index]) / 32_768))
                } else if let values = buffer.int32ChannelData {
                    peak = max(peak, abs(Float(values[channel][index]) / 2_147_483_648))
                }
            }
        }
        return peak
    }
}

private final class AudioFileWriter: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let startTime: CMTime
    private var appendedSamples = false

    init(url: URL, firstSample: CMSampleBuffer) throws {
        guard let format = firstSample.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { throw CocoaError(.fileWriteUnknown) }
        writer = try AVAssetWriter(outputURL: url, fileType: .m4a)
        input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: asbd.mSampleRate,
                AVNumberOfChannelsKey: Int(asbd.mChannelsPerFrame),
                AVEncoderBitRateKey: asbd.mChannelsPerFrame == 1 ? 64_000 : 128_000,
            ],
            sourceFormatHint: format
        )
        startTime = firstSample.presentationTimeStamp
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else { throw CocoaError(.fileWriteUnknown) }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: startTime)
    }

    func append(_ sample: CMSampleBuffer) throws {
        guard input.isReadyForMoreMediaData, input.append(sample) else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }
        appendedSamples = true
    }

    func finish(videoStart: CMTime?) async throws -> CapturedRecordingAudio.Track? {
        guard appendedSamples else {
            writer.cancelWriting()
            return nil
        }
        guard writer.status == .writing else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        let offset = videoStart.map { CMTimeSubtract(startTime, $0) } ?? .zero
        return CapturedRecordingAudio.Track(url: writer.outputURL, offset: offset)
    }
}
