import AVFoundation
import Foundation

enum VideoCodecOption: String, CaseIterable {
    case h264
    case hevc

    var codecType: AVVideoCodecType {
        switch self {
        case .h264:
            return .h264
        case .hevc:
            return .hevc
        }
    }

    var title: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "HEVC (H.265)"
        }
    }
}
