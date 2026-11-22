import SwiftUI

/// Shared observable color settings for the hexagon overlay.
@Observable
final class OverlayColors {
    static let shared = OverlayColors()

    var partial      = Color(red: 1, green: 1, blue: 1.0).opacity(1)
    var partialWidth = 0.5
//    var partialFill  = Color.white.opacity(0.0)

    var dense        = Color(red: 1, green: 1, blue: 1).opacity(0.5)
    var denseWidth   = 1.0
    var denseFill    = Color.white.opacity(0.2)

    var full         = Color(red: 1, green: 0, blue: 1).opacity(1.0)
    var fullWidth    = 1.0
    var fullFill     = Color(red:1, green:0, blue:1).opacity(0.2)

    private init() {}
}
