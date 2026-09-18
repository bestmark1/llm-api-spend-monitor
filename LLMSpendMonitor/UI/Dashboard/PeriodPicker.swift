import AppKit
import SwiftUI

/// The reporting period as a capsule track. Everything else in the panel is
/// round — the panel, the cards, the header buttons, Options — and the system
/// segmented control was the one square element left.
///
/// Each segment is its own accessible button that reports whether it is
/// selected. An accessibility representation of the system control was
/// tried first: its segments sat where the system control would put them,
/// not where these are, so a click on "30 Days" landed on "Yesterday".
struct PeriodPicker: View {
    @Binding var selection: DashboardPeriod

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var showsFocusRing = false
    @Namespace private var selectionSpace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DashboardPeriod.allCases) { period in
                segment(period)
            }
        }
        .padding(2)
        .frame(height: 28)
        .background(Color.primary.opacity(0.10), in: Capsule())
        .overlay {
            if showsFocusRing {
                Capsule().strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 2)
            }
        }
        .frame(maxWidth: .infinity)
        .focusable()
        .focused($isFocused)
        // A click on a segment focuses the track too. The ring is for someone
        // who reached it with the keyboard, so it shows only when a key press
        // moved the focus here.
        .onChange(of: isFocused) { _, focused in
            showsFocusRing = focused && NSApp.currentEvent?.type == .keyDown
        }
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1) }
        .onKeyPress(.rightArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Reporting period")
        .accessibilityIdentifier("dashboard.period")
    }

    private func segment(_ period: DashboardPeriod) -> some View {
        let isSelected = period == selection

        return Button {
            select(period)
        } label: {
            Text(period.title)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.accentColor)
                            .matchedGeometryEffect(id: "selection", in: selectionSpace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(period.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ period: DashboardPeriod) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            selection = period
        }
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        let all = DashboardPeriod.allCases
        guard
            let index = all.firstIndex(of: selection),
            all.indices.contains(index + offset)
        else { return .handled }
        select(all[index + offset])
        return .handled
    }
}
