import SwiftUI
import UIKit

/// The app's colour, taken from the app icon.
///
/// The icon is warm — cream paper, a terracotta line, a sand disc — while the interface was
/// stock iOS blue, orange, green and red. Two different products. Every value below is either
/// sampled straight from the icon (`terracotta` is the icon's own stroke, `canvas` its
/// background) or mixed to sit in the same family.
///
/// Roles, not shades: a view asks for `.due` or `.destructive`, never for "orange". That is
/// the whole point — it is what lets the palette move in one place instead of nineteen.
///
/// Two variants of each hue. The plain one is for fills, strokes and glyphs, where the icon's
/// exact colour is more faithful than a darkened version of it and 3:1 is the bar. The `Text`
/// one is darkened (lightened in dark mode) to clear WCAG AA 4.5:1 against `canvas`, and is
/// the only one that may sit under type.
///
/// Nothing here tints a glass surface: `docs/ux-principles.md` §36 forbids it, and it is also
/// unnecessary. Glass takes its colour from whatever it is over, so warming the canvas warms
/// every surface in the app for free.
enum Palette {
    // MARK: - Surfaces

    /// The backdrop the whole app sits on, and therefore the thing the glass samples.
    /// A slow vertical fall from the icon's cream to its sand — enough to give the material
    /// something to lens, not enough to notice as a gradient.
    static var canvas: LinearGradient {
        LinearGradient(
            colors: [
                // Dark is warm charcoal, not black. Pulled far enough off neutral that the
                // red channel is visible: at OLED black the app loses its colour entirely
                // and reads as a different product again after dark.
                Color(light: 0xF7EDE0, dark: 0x1B1611),
                Color(light: 0xF3E5D4, dark: 0x2A2018)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Opaque warm paper, for the surfaces that are not glass: the study card, where text can
    /// never be allowed to fight a blurred background, and list rows, which iOS would
    /// otherwise paint its own neutral grey.
    static let paper = Color(light: 0xFCF6EE, dark: 0x33291F)

    // MARK: - Hues

    /// The icon's own stroke colour.
    static let terracotta = Color(light: 0xB6734F, dark: 0xD9906A)
    static let terracottaText = Color(light: 0x8E5335, dark: 0xE0A183)

    static let sage = Color(light: 0x6E7F5E, dark: 0x9CB08A)
    static let sageText = Color(light: 0x5A6E4C, dark: 0xA8BC96)

    static let brick = Color(light: 0xA6473A, dark: 0xE08A78)

    static let slate = Color(light: 0x5E7280, dark: 0x9BB0BE)
    static let slateText = Color(light: 0x4F626F, dark: 0xA8BCC8)

    // MARK: - Roles

    /// Work that has come round again. The loudest state, so it gets the icon's own hue.
    static let due = terracotta
    static let dueText = terracottaText

    /// Cards not yet seen. Cool and quiet: nothing is overdue about them.
    static let new = slate
    static let newText = slateText

    /// Finished, caught up, imported cleanly.
    static let success = sage
    static let successText = sageText

    /// Something the user should look at but nothing is broken.
    static let warning = terracottaText

    /// Deleting, failing, and the "again" grade.
    static let destructive = brick
}

private extension Color {
    /// Builds a colour that resolves per appearance, so no view ever branches on dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
