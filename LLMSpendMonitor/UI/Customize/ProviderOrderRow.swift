import SwiftUI

struct ProviderOrderRow: View {
    let item: CustomizeViewModel.Item
    let position: Int
    let total: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let setVisible: (Bool) -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    @State private var isVisible: Bool

    init(
        item: CustomizeViewModel.Item,
        position: Int,
        total: Int,
        canMoveUp: Bool,
        canMoveDown: Bool,
        setVisible: @escaping (Bool) -> Void,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void
    ) {
        self.item = item
        self.position = position
        self.total = total
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.setVisible = setVisible
        self.moveUp = moveUp
        self.moveDown = moveDown
        _isVisible = State(initialValue: item.isVisible)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Image(systemName: item.metadata.systemImageName)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(item.isVisible ? .primary : .tertiary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.metadata.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(item.isVisible ? .primary : .secondary)
                Text(capabilitySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 2) {
                Button("Move \(item.metadata.displayName) up", systemImage: "chevron.up", action: moveUp)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!canMoveUp)
                    .accessibilityIdentifier("customize.\(item.id.rawValue).moveUp")

                Button("Move \(item.metadata.displayName) down", systemImage: "chevron.down", action: moveDown)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(!canMoveDown)
                    .accessibilityIdentifier("customize.\(item.id.rawValue).moveDown")
            }

            Toggle(
                "Show \(item.metadata.displayName)",
                isOn: $isVisible
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityIdentifier("customize.\(item.id.rawValue).visible")
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.metadata.displayName)
        .accessibilityValue("Position \(position) of \(total), \(item.isVisible ? "shown" : "hidden")")
        .accessibilityIdentifier("customize.\(item.id.rawValue).row")
        .onChange(of: item.isVisible) { _, newValue in
            isVisible = newValue
        }
        .onChange(of: isVisible) { _, newValue in
            guard newValue != item.isVisible else { return }
            setVisible(newValue)
        }
    }

    private var capabilitySummary: String {
        if item.metadata.integrationAvailability == .planned {
            return "Integration planned"
        }
        if item.metadata.capabilities.contains(.officialCostHistory) {
            return "Official spend · tokens · models"
        }
        if item.metadata.capabilities.contains(.balance) {
            return "Current official balance"
        }
        return "Connection validation only"
    }
}
