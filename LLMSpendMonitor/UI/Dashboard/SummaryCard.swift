import SwiftUI

struct SummaryCard: View {
    let total: Money
    let breakdown: [ProviderSpendSummary]
    let dailySpend: [DailySpendPoint]
    let excludedProviderCount: Int
    let estimatedProviderCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Tracked spend")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(MetricFormatting.money(total))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: decimalValue(total.amount)))
                    statusLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if breakdown.count > 1 {
                    SpendDonutChart(breakdown: breakdown)
                }
            }

            if !breakdown.isEmpty {
                Divider()
                providerLegend
            }

            if dailySpend.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Daily trend")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    SpendTrendChart(points: dailySpend)
                }
            }
        }
        .padding(18)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.summary")
    }

    @ViewBuilder
    private var statusLabel: some View {
        if excludedProviderCount > 0 {
            Label(
                "Partial · \(excludedProviderCount) report\(excludedProviderCount == 1 ? "" : "s") excluded",
                systemImage: "exclamationmark.circle.fill"
            )
            .foregroundStyle(.orange)
            .accessibilityIdentifier("dashboard.summary.partial")
        } else if estimatedProviderCount > 0 {
            Label(
                "Official reports · (estimatedProviderCount) balance estimate\(estimatedProviderCount == 1 ? "" : "s")",
                systemImage: "equal.circle.fill"
            )
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("dashboard.summary.estimated")
        } else {
            Label("Complete official USD reports", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("dashboard.summary.complete")
        }
    }

    private var providerLegend: some View {
        VStack(spacing: 7) {
            ForEach(breakdown) { summary in
                HStack(spacing: 8) {
                    Circle()
                        .fill(ProviderVisualStyle.color(for: summary.providerID))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(providerName(summary.providerID))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(MetricFormatting.money(summary.amount))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }
                .font(.callout)
                .help(summary.provenance == .estimated
                    ? "Estimated from saved balance decreases for \(providerName(summary.providerID))"
                    : "Official spend reported by \(providerName(summary.providerID))")
            }
        }
    }

    private func providerName(_ providerID: ProviderID) -> String {
        ProviderRegistry.metadata(for: providerID)?.displayName ?? providerID.rawValue
    }

    private func decimalValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }
}
