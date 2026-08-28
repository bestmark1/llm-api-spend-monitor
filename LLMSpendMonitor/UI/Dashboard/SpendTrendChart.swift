import Charts
import SwiftUI

struct SpendTrendChart: View {
    let points: [DailySpendPoint]

    var body: some View {
        VStack(spacing: 3) {
            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Daily spend", decimalValue(point.amount.amount))
                )
                .foregroundStyle(.tint)
                .cornerRadius(2)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 48)

            if let first = points.first?.date, let last = points.last?.date {
                HStack {
                    Text(shortDate(first))
                    Spacer()
                    Text(shortDate(last))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Daily spend")
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

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
