import SwiftUI

struct MenuBarLabelView: View {
    private static let zeroUSD = try! Money(amount: 0, currencyCode: "USD")

    static let metricText = metricText(for: zeroUSD)
    static let accessibilityLabel = accessibilityLabel(for: zeroUSD)

    static func metricText(for total: Money) -> String {
        MetricFormatting.money(total)
    }

    static func accessibilityLabel(for total: Money) -> String {
        "LLM API spend today: \(metricText(for: total))"
    }

    var body: some View {
        Label(Self.metricText, systemImage: "chart.bar.fill")
            .accessibilityLabel(Self.accessibilityLabel)
    }
}
