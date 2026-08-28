import Charts
import SwiftUI

struct SpendDonutChart: View {
    let breakdown: [ProviderSpendSummary]

    var body: some View {
        Chart(breakdown) { summary in
            SectorMark(
                angle: .value("Tracked spend", decimalValue(summary.amount.amount)),
                innerRadius: .ratio(0.68),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(ProviderVisualStyle.color(for: summary.providerID))
        }
        .chartLegend(.hidden)
        .frame(width: 96, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tracked spend distribution")
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("dashboard.spendDistribution")
    }

    private var accessibilitySummary: String {
        breakdown.map { summary in
            let provider = ProviderRegistry.metadata(for: summary.providerID)?.displayName
                ?? summary.providerID.rawValue
            return "\(provider), \(MetricFormatting.money(summary.amount))"
        }
        .joined(separator: ", ")
    }

    private func decimalValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }
}
