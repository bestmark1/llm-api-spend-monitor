import SwiftUI

struct PeriodPicker: View {
    @Binding var selection: DashboardPeriod

    var body: some View {
        Picker("Reporting period", selection: $selection) {
            ForEach(DashboardPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("dashboard.period")
    }
}
