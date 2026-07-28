import SwiftUI

/// Press feedback on touch-down (`docs/ux-principles.md` §4).
///
/// A `ButtonStyle` is the only correct way to do this: `configuration.isPressed` flips the
/// instant the finger lands, and unlike a `simultaneousGesture` it cannot swallow the
/// button's own action.
struct PressableGlassButtonStyle: ButtonStyle {
    var prominence: GlassSurface.Prominence = .prominent
    var cornerRadius: CGFloat = Spacing.cardCornerRadius

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassSurface(prominence, cornerRadius: cornerRadius)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// The one control a screen is built around.
///
/// Deliberately large, always in the same position, and acknowledged the moment it is
/// touched rather than when the finger lifts.
struct PrimaryActionButton: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.normal) {
                Image(systemName: systemImage)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(Spacing.normal)
            .frame(maxWidth: .infinity, minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableGlassButtonStyle())
    }
}
