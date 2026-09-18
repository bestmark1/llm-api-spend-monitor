import AppKit
import Charts
import SwiftUI

struct SpendTrendChart: View {
    let points: [DailySpendPoint]
    /// Ties within the stacking order, largest spender first.
    var providerOrder: [ProviderID] = []
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var colorScheme

    private static let plotHeight: CGFloat = 64

    /// One stacked bar per day, one segment per provider, in the provider's
    /// own colour — the colours of the composition bar and legend right above.
    /// A flat grey read as disabled, and every free hue is already a provider
    /// or a status, so the chart borrows the meaning that is already there.
    var body: some View {
        VStack(spacing: 3) {
            Chart {
                ForEach(segments) { segment in
                    BarMark(
                        x: .value("Day", segment.date, unit: .day),
                        yStart: .value("From", segment.start),
                        yEnd: .value("To", segment.end)
                    )
                    .foregroundStyle(ProviderVisualStyle.color(for: segment.providerID))
                    .opacity(selectedDate == nil || selectedDate == segment.date ? 1 : 0.35)
                    .cornerRadius(segment.isTop ? 2 : 0)
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
            .chartYScale(domain: 0...peak)
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
            .frame(height: Self.plotHeight)

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

    private struct Segment: Identifiable {
        let date: Date
        let providerID: ProviderID
        let start: Double
        let end: Double
        let isTop: Bool

        var id: String { "\(date.timeIntervalSince1970)-\(providerID.rawValue)" }
    }

    private var peak: Double {
        max(points.map { decimalValue($0.amount.amount) }.max() ?? 0, 0.000_001)
    }

    private var segments: [Segment] {
        // One point of the plot, in dollars at this chart's scale. Segments
        // are parted by a one-point seam of card, but only where both sides
        // are at least three points tall: on a small day the seams ate the
        // segments and the bar broke into a stack of slivers.
        let point = peak / Double(Self.plotHeight)
        let seam = point
        let minimumForSeam = 3 * point
        return points.flatMap { day -> [Segment] in
            let shares = orderedShares(day)
            var result: [Segment] = []
            var floor = 0.0
            for (index, share) in shares.enumerated() {
                let parted = index > 0
                    && shares[index - 1].amount >= minimumForSeam
                    && share.amount >= minimumForSeam
                let start = floor + (parted ? seam : 0)
                let end = floor + share.amount
                floor = end
                guard end > start else { continue }
                result.append(Segment(
                    date: day.date,
                    providerID: share.providerID,
                    start: start,
                    end: end,
                    isTop: false
                ))
            }
            if let last = result.popLast() {
                result.append(Segment(
                    date: last.date,
                    providerID: last.providerID,
                    start: last.start,
                    end: last.end,
                    isTop: true
                ))
            }
            return result
        }
    }

    /// Bottom to top: the provider that stands out most against the card
    /// first, the faintest last. With the darkest colour on top, every bar
    /// wore a black cap and the chart's outline read as a dotted black line;
    /// at the base the same colour is ground rather than outline. In dark
    /// mode the order flips, because there the light colours stand out.
    private func orderedShares(_ point: DailySpendPoint) -> [(providerID: ProviderID, amount: Double)] {
        let rank = Dictionary(
            providerOrder.enumerated().map { ($1, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        func prominence(_ id: ProviderID) -> Double {
            let lightness = Self.luminance(of: ProviderVisualStyle.color(for: id), in: appearance)
            return colorScheme == .dark ? lightness : 1 - lightness
        }
        return point.byProvider
            .filter { $0.value > 0 }
            .sorted {
                let left = prominence($0.key)
                let right = prominence($1.key)
                if abs(left - right) > 0.001 { return left > right }
                let leftRank = rank[$0.key] ?? Int.max
                let rightRank = rank[$1.key] ?? Int.max
                return leftRank != rightRank ? leftRank < rightRank : $0.value > $1.value
            }
            .map { ($0.key, decimalValue($0.value)) }
    }

    /// Relative luminance of a colour as it resolves in `appearance`.
    private static func luminance(of color: Color, in appearance: NSAppearance?) -> Double {
        var result = 0.5
        let resolve = {
            guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
            func linear(_ c: CGFloat) -> Double {
                let v = Double(c)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            result = 0.2126 * linear(rgb.redComponent)
                + 0.7152 * linear(rgb.greenComponent)
                + 0.0722 * linear(rgb.blueComponent)
        }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(resolve)
        } else {
            resolve()
        }
        return result
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
