import SwiftUI

/// The single place in Flash Up that knows Liquid Glass exists only from iOS 26 (see
/// `docs/ux-principles.md`).
///
/// On iOS 26 and later this is the real system material, so the app inherits Apple's
/// lensing, motion and legibility behaviour for free. Below it, a translucent material
/// approximates the look. Layout is identical on both paths — only the surface changes —
/// so there is one design to maintain, not two.
///
/// No other view may branch on the OS version for appearance.
struct GlassSurface: ViewModifier {
    enum Prominence {
        /// Chrome and cards: recedes behind its content.
        case regular
        /// Controls the user is meant to reach for first.
        case prominent
    }

    let prominence: Prominence
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                prominence == .prominent ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            content
                .background(fallbackMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    // A bright top edge reads as light catching a real material.
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
                }
        }
    }

    private var fallbackMaterial: Material {
        switch prominence {
        case .regular: .ultraThinMaterial
        case .prominent: .thinMaterial
        }
    }
}

extension View {
    /// Places the view on a glass surface.
    func glassSurface(
        _ prominence: GlassSurface.Prominence = .regular,
        cornerRadius: CGFloat = Spacing.cardCornerRadius
    ) -> some View {
        modifier(GlassSurface(prominence: prominence, cornerRadius: cornerRadius))
    }
}
