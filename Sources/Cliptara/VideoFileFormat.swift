import AVFoundation
import Foundation

enum VideoFileFormat: String, CaseIterable {
    case mov
    case mp4

    var fileType: AVFileType {
        switch self {
        case .mov:
            return .mov
        case .mp4:
            return .mp4
        }
    }

    var fileExtension: String {
        switch self {
        case .mov:
            return "mov"
        case .mp4:
            return "mp4"
        }
    }

    var title: String {
        switch self {
        case .mov:
            return "MOV"
        case .mp4:
            return "MP4"
        }
    }
}
