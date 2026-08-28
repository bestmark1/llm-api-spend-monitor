import SwiftUI

struct CustomizeProvidersView: View {
    @ObservedObject var viewModel: CustomizeViewModel
    let showDashboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("Providers")
                    .font(.headline)
                Text("Drag to reorder, or use the arrow buttons. Changes are saved automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            List {
                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    ProviderOrderRow(
                        item: item,
                        position: index + 1,
                        total: viewModel.items.count,
                        canMoveUp: index > 0,
                        canMoveDown: index + 1 < viewModel.items.count,
                        setVisible: { viewModel.setVisible($0, for: item.id) },
                        moveUp: { moveUp(item) },
                        moveDown: { moveDown(item) }
                    )
                }
                .onMove(perform: move)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(.clear)
        .accessibilityIdentifier("customize.root")
    }

    private var header: some View {
        HStack {
            Button("Back", systemImage: "chevron.left", action: showDashboard)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .accessibilityIdentifier("customize.back")

            Spacer()

            Text("Customize")
                .font(.title3.bold())

            Spacer()

            Button("Reset provider order and visibility", systemImage: "arrow.counterclockwise") {
                viewModel.reset()
                announce("Provider order and visibility reset")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .accessibilityIdentifier("customize.reset")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func move(_ offsets: IndexSet, _ destination: Int) {
        viewModel.move(fromOffsets: offsets, toOffset: destination)
        announce("Provider order updated")
    }

    private func moveUp(_ item: CustomizeViewModel.Item) {
        guard let index = viewModel.moveUp(item.id) else { return }
        announce("\(item.metadata.displayName), position \(index + 1) of \(viewModel.items.count)")
    }

    private func moveDown(_ item: CustomizeViewModel.Item) {
        guard let index = viewModel.moveDown(item.id) else { return }
        announce("\(item.metadata.displayName), position \(index + 1) of \(viewModel.items.count)")
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }
}
