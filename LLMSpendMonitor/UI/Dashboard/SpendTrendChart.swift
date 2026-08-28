import Charts
import SwiftUI

struct SpendTrendChart: View {
    let points: [DailySpendPoint]

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Tracked spend", decimalValue(point.amount.amount))
            )
            .foregroundStyle(.tint)
            .cornerRadius(2)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 42)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily tracked spend trend")
        .accessibilityValue(accessibilitySummary)
        .accessibilityIdentifier("dashboard.spendTrend")
    }

    private var accessibilitySummary: String {
        points.map { point in
            "\(point.date.formatted(date: .abbreviated, time: .omitted)), \(MetricFormatting.money(point.amount))"
        }
        .joined(separator: ", ")
    }

    private func decimalValue(_ decimal: Decimal) -> Double {
        NSDecimalNumber(decimal: decimal).doubleValue
    }
}
