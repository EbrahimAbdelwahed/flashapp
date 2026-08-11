import SwiftUI

/// One of the two numbers that tell the user how much work is waiting.
///
/// The number is the loudest thing on the screen; the label explains it. VoiceOver reads
/// them as one element so it says "12 da ripassare", not "12" then "da ripassare".
struct CountTile: View {
    let value: Int
    let caption: LocalizedStringKey
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)

            Text(value, format: .number)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .contentTransition(.numericText())
                .monospacedDigit()

            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.normal)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }
}

/// Shown instead of the study button when there is nothing left to review — an empty state
/// that congratulates rather than a bare "no items" (`docs/ux-principles.md` §2).
struct CaughtUpCard: View {
    let streakDays: Int

    var body: some View {
        VStack(spacing: Spacing.tight) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(Palette.success)
            Text("today.caught_up")
                .font(.headline)
            if streakDays > 0 {
                Text("today.streak \(streakDays)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.loose)
        .glassSurface()
        .accessibilityElement(children: .combine)
    }
}
