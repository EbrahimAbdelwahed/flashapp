import SwiftUI

/// The persistent brand lockup shared by every root tab.
///
/// Keeping the lockup here prevents the four primary screens from drifting apart as their
/// individual navigation actions evolve.
struct AppBrandHeader<Trailing: View>: View {
    @ViewBuilder private let trailing: Trailing

    init(@ViewBuilder trailing: () -> Trailing) {
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Spacing.normal) {
            AppBrandMark()

            Spacer(minLength: Spacing.tight)

            trailing
        }
        .padding(.horizontal, Spacing.normal)
        .padding(.vertical, Spacing.tight)
    }
}

extension AppBrandHeader where Trailing == EmptyView {
    init() {
        self.init { EmptyView() }
    }
}

private struct AppBrandMark: View {
    @ScaledMetric(relativeTo: .title2) private var logoSize = 42.0

    var body: some View {
        HStack(spacing: Spacing.tight) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                // The artwork contains its own breathing room. A larger frame lets the
                // visible monogram overshoot the wordmark above and below, as in the mark.
                .frame(width: logoSize, height: logoSize)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            Text("FlashApp")
                .font(.title2.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FlashApp")
        .accessibilityIdentifier("app.brand")
    }
}
