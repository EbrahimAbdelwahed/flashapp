import SwiftUI

/// Spacing and shape constants.
///
/// Every value here is a deliberate choice, not a number typed at the call site: a shared
/// scale is what makes unrelated screens feel like one app.
enum Spacing {
    static let tight: CGFloat = 8
    static let normal: CGFloat = 16
    static let loose: CGFloat = 24
    static let sectionGap: CGFloat = 32

    static let cardCornerRadius: CGFloat = 20
    static let controlCornerRadius: CGFloat = 14

    /// Minimum height of anything tappable, per Apple's 44pt target.
    static let minimumTapTarget: CGFloat = 44
}

/// Motion, per `docs/ux-principles.md` §4: springs rather than durations, and reduced
/// motion means a gentler animation, not the absence of feedback.
enum Motion {
    /// Default for anything that simply appears or moves.
    static let standard: Animation = .smooth(duration: 0.35)
    /// Control feedback that should feel immediate.
    static let snappy: Animation = .snappy(duration: 0.25)

    /// The animation to use given the user's reduced-motion setting.
    static func reveal(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.2) : standard
    }
}
