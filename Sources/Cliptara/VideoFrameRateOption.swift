import Foundation

enum VideoFrameRateOption: String, CaseIterable {
    case fps24
    case fps30
    case fps60

    var fps: Int {
        switch self {
        case .fps24:
            return 24
        case .fps30:
            return 30
        case .fps60:
            return 60
        }
    }

    var title: String {
        "\(fps) FPS"
    }
}
