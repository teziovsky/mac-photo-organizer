import Foundation

enum ThumbnailDisplayMode: String, CaseIterable, Sendable {
    case square
    case fit

    mutating func toggle() {
        self = self == .square ? .fit : .square
    }

    var toolbarLabel: String {
        switch self {
        case .square:
            "Square Thumbnails"
        case .fit:
            "Original Aspect Ratio"
        }
    }

    var toolbarIcon: String {
        switch self {
        case .square:
            "rectangle.arrowtriangle.2.inward"
        case .fit:
            "rectangle.arrowtriangle.2.outward"
        }
    }
}
