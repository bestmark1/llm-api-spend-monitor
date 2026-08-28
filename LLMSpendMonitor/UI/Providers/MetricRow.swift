import Foundation
import SwiftUI

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

enum MetricFormatting {
    static func money(_ money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = money.currencyCode
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: money.amount))
            ?? "\(money.currencyCode) —"
    }

    static func tokens(_ value: Int64) -> String {
        let magnitude = abs(Double(value))
        let unit: (divisor: Double, suffix: String)? = if magnitude >= 1_000_000_000 {
            (1_000_000_000, "B")
        } else if magnitude >= 1_000_000 {
            (1_000_000, "M")
        } else if magnitude >= 1_000 {
            (1_000, "K")
        } else {
            nil
        }
        guard let unit else { return String(value) }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        formatter.roundingMode = .halfUp
        let compactValue = Double(value) / unit.divisor
        return "\(formatter.string(from: NSNumber(value: compactValue)) ?? String(compactValue))\(unit.suffix)"
    }
}
