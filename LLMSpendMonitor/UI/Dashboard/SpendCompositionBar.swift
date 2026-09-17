import SwiftUI

/// One horizontal bar showing what the total is made of.
///
/// Part-to-whole is read more accurately from length along a common baseline than
/// from angle or area, and a bar also uses the card's width — which a ring, being
/// square, never could.
struct SpendCompositionBar: View {
    let breakdown: [ProviderSpendSummary]

    private let height: CGFloat = 11
    private let gap: CGFloat = 2
    /// A provider that spent almost nothing still gets a visible sliver, so the bar
    /// never silently drops a connected provider. It costs a little proportional
    /// accuracy at the bottom of the range; the amounts below the bar are exact.
    private let minimumSegment: CGFloat = 5

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: gap) {
                ForEach(Array(widths(in: proxy.size.width).enumerated()), id: \.offset) { index, width in
                    segment(for: breakdown[index], width: width)
                }
            }
        }
        .frame(height: height)
        .shadow(color: .black.opacity(reduceTransparency ? 0.04 : 0.16), radius: 3, y: 1.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spend composition")
        .accessibilityIdentifier("dashboard.spendComposition")
    }

    /// Borrows the app's own material: the highlight, hairline and shadow are the
    /// ones GlassSurface uses, so the bar gains depth from the system it lives in
    /// rather than from an effect invented for it.
    private func segment(for summary: ProviderSpendSummary, width: CGFloat) -> some View {
        Capsule()
            .fill(ProviderVisualStyle.color(for: summary.providerID))
            .overlay {
                if !reduceTransparency {
                    Capsule().fill(
                        LinearGradient(
                            colors: [.white.opacity(0.30), .white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            }
            .overlay {
                Capsule().strokeBorder(
                    .white.opacity(colorScheme == .dark ? 0.16 : 0.34),
                    lineWidth: 0.5
                )
            }
            .frame(width: width)
    }

    private func widths(in available: CGFloat) -> [CGFloat] {
        let usable = max(0, available - gap * CGFloat(max(0, breakdown.count - 1)))
        let amounts = breakdown.map { NSDecimalNumber(decimal: $0.amount.amount).doubleValue }
        let total = amounts.reduce(0, +)
        guard total > 0, usable > 0 else {
            let equal = usable / CGFloat(max(1, breakdown.count))
            return Array(repeating: equal, count: breakdown.count)
        }

        var widths = amounts.map { max(minimumSegment, usable * CGFloat($0 / total)) }
        // Raising the small segments overshoots the row; take the excess back from the
        // largest one, which can spare it without changing how the bar reads.
        let overflow = widths.reduce(0, +) - usable
        if overflow > 0, let widest = widths.indices.max(by: { widths[$0] < widths[$1] }) {
            widths[widest] = max(minimumSegment, widths[widest] - overflow)
        }
        return widths
    }
}
