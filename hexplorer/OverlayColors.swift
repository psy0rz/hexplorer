import SwiftUI

/// Shared observable color settings for the hexagon overlay.
@Observable
final class OverlayColors {
    static let shared = OverlayColors()

    var partial      = Color(red: 0.8, green: 0.8, blue: 0.8).opacity(1)
    var partialWidth = 1.0

    var dense        = Color(red: 1, green: 1, blue: 0).opacity(1)
    var denseWidth   = 1.0
    var denseFill    = Color(red:1, green:1, blue:0).opacity(0.2)

    var full         = Color(red: 1, green: 0, blue: 1).opacity(1.0)
    var fullWidth    = 1.0
    var fullFill     = Color(red:1, green:0, blue:1).opacity(0.2)

    /// Dark line below the outlines of all visited cells, so they stay visible on light backgrounds.
    /// It is wider than the outlines; the difference is split over both sides.
    var halo         = Color.black.opacity(1)
    var haloWidth    = 2.0

    private init() {}
}
