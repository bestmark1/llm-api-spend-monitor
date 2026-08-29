import Charts
import SwiftUI

struct SpendTrendChart: View {
    let points: [DailySpendPoint]
    @State private var selectedDate: Date?

    var body: some View {
        VStack(spacing: 3) {
            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Daily spend", decimalValue(point.amount.amount))
                    )
                    .foregroundStyle(
                        selectedDate == nil || selectedDate == point.date
                            ? Color.accentColor
                            : Color.accentColor.opacity(0.35)
                    )
                    .cornerRadius(2)
                }

                if let selectedPoint {
                    RuleMark(x: .value("Selected day", selectedPoint.date, unit: .day))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(shortDate(selectedPoint.date))
                                Text(MetricFormatting.money(selectedPoint.amount))
                                    .fontWeight(.semibold)
                                    .monospacedDigit()
                            }
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                        }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            updateSelection(
                                for: phase,
                                proxy: proxy,
                                geometry: geometry
                            )
                        }
                }
            }
            .frame(height: 64)

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

    private var selectedPoint: DailySpendPoint? {
        guard let selectedDate else { return nil }
        return points.first { $0.date == selectedDate }
    }

    private func updateSelection(
        for phase: HoverPhase,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        switch phase {
        case .active(let location):
            guard let plotFrameAnchor = proxy.plotFrame else {
                selectedDate = nil
                return
            }
            let plotFrame = geometry[plotFrameAnchor]
            guard plotFrame.contains(location) else {
                selectedDate = nil
                return
            }
            let plotX = location.x - plotFrame.minX
            guard let hoveredDate: Date = proxy.value(atX: plotX) else {
                selectedDate = nil
                return
            }
            selectedDate = points.min {
                abs($0.date.timeIntervalSince(hoveredDate))
                    < abs($1.date.timeIntervalSince(hoveredDate))
            }?.date
        case .ended:
            selectedDate = nil
        }
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
