import SwiftUI

struct MenuBarLabelView: View {
    static let metricText = "$0.00"
    static let accessibilityLabel = "LLM API spend today: $0.00"

    var body: some View {
        Label(Self.metricText, systemImage: "chart.bar.fill")
            .accessibilityLabel(Self.accessibilityLabel)
    }
}
