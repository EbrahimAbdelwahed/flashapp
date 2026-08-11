import SwiftUI

/// Puts a screen on the app's warm canvas.
///
/// This is the modifier that makes the glass warm. `GlassSurface` deliberately never names a
/// colour — on iOS 26 the real material lenses whatever is behind it, and below it the
/// fallback `Material` does the same — so the backdrop is the only place the app's tone can
/// come from. A screen that forgets this is the one screen that still looks like stock iOS.
///
/// `scrollContentBackground(.hidden)` is what lets it through a `List` or `Form`, which
/// otherwise paints the system grouped background over the top and wins.
private struct ScreenCanvas: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background {
                ZStack {
                    Palette.canvas.ignoresSafeArea()

                    MonogramSignatureDecoration()
                        .frame(width: 320, height: 320)
                        .offset(x: 85, y: -205)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
    }
}

/// The logo's own linework, let into the canvas as a quiet signature rather than a second
/// surface. Inverting luminance removes the icon's paper field, leaving only its monogram.
private struct MonogramSignatureDecoration: View {
    var body: some View {
        Palette.terracotta
            .mask {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .colorInvert()
                    .luminanceToAlpha()
            }
            .opacity(0.31)
            .rotationEffect(.degrees(-12))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    /// Applies to the scrolling root of a screen — the `List`, `Form` or `ScrollView`
    /// itself, not the `NavigationStack` around it, or the navigation bar keeps its own
    /// background and the seam shows.
    func screenCanvas() -> some View {
        modifier(ScreenCanvas())
    }

    /// Puts list rows on warm paper.
    ///
    /// `screenCanvas()` only clears the *list's* background; each row still paints the system
    /// grouped grey and would sit on the warm canvas as a cold island. This has to go on the
    /// `Section` (or on the rows themselves where a list has none) — SwiftUI does not carry
    /// `listRowBackground` down from the `List`.
    func paperRows() -> some View {
        listRowBackground(Palette.paper)
    }
}
