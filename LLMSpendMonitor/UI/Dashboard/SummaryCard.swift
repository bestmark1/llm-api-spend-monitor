import SwiftUI

struct SummaryCard: View {
    let total: Money
    let breakdown: [ProviderSpendSummary]
    let dailySpend: [DailySpendPoint]
    let excludedProviderCount: Int
    let showsDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        Text("Tracked spend")
                            .font(.callout.weight(.medium))
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .help("Official provider reports plus clearly labeled estimates when an official spend API is unavailable.")
                            .accessibilityLabel("About tracked spend")
                    }
                    .foregroundStyle(.secondary)
                    Text(MetricFormatting.money(total))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: decimalValue(total.amount)))
                    if let provenanceSummary {
                        Text(provenanceSummary)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("dashboard.summary.provenance")
                    }
                    if excludedProviderCount > 0 {
                        Label(
                            "Partial · \(excludedProviderCount) report\(excludedProviderCount == 1 ? "" : "s") excluded",
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("dashboard.summary.partial")
                    }
                    if !showsDetails, !breakdown.isEmpty {
                        compactProviderLegend
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !breakdown.isEmpty {
                    SpendDonutChart(breakdown: breakdown)
                }
            }

            if showsDetails, !breakdown.isEmpty {
                Divider()
                providerLegend
            }

            if showsDetails, dailySpend.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Daily spend")
                            .font(.caption.weight(.medium))
                        Spacer()
                        if let peakDailySpend {
                            Text("Peak \(MetricFormatting.money(peakDailySpend))")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    }
                    .foregroundStyle(.secondary)
                    SpendTrendChart(points: dailySpend)
                }
            }
        }
        .padding(18)
        .background {
            GlassSurface(cornerRadius: 16, prominence: .primary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard.summary")
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
                    provenanceBadge(summary.provenance)
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
        .accessibilityIdentifier("dashboard.providerBreakdown")
    }

    private var compactProviderLegend: some View {
        HStack(spacing: 12) {
            ForEach(breakdown) { summary in
                HStack(spacing: 5) {
                    Circle()
                        .fill(ProviderVisualStyle.color(for: summary.providerID))
                        .frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(providerName(summary.providerID))
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("dashboard.compactProviderLegend")
    }

    private var peakDailySpend: Money? {
        dailySpend.max { $0.amount.amount < $1.amount.amount }?.amount
    }

    private var hasEstimatedSpend: Bool {
        breakdown.contains { $0.provenance == .estimated }
    }

    private var provenanceSummary: String? {
        guard !breakdown.isEmpty else { return nil }
        let hasOfficial = breakdown.contains { $0.provenance == .official }
        return switch (hasOfficial, hasEstimatedSpend) {
        case (true, true): "Official + estimated data"
        case (true, false): "Official provider reports"
        case (false, true): "Estimated provider data"
        case (false, false): nil
        }
    }

    private func provenanceBadge(_ provenance: MetricProvenance) -> some View {
        Text(provenance == .estimated ? "Estimated" : "Official")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
    }

    private func providerName(_ providerID: ProviderID) -> String {
        ProviderRegistry.metadata(for: providerID)?.displayName ?? providerID.rawValue
    }

    private func decimalValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }
}
