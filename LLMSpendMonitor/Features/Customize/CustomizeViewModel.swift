import SwiftUI

@MainActor
final class CustomizeViewModel: ObservableObject {
    struct Item: Identifiable, Equatable {
        let metadata: ProviderMetadata
        var isVisible: Bool

        var id: ProviderID { metadata.id }
    }

    @Published private(set) var items: [Item]

    private let registry: [ProviderMetadata]
    private let store: any ProviderCustomizationStoring

    var visibleProviderIDs: [ProviderID] {
        items.compactMap { $0.isVisible ? $0.id : nil }
    }

    init(
        registry: [ProviderMetadata] = ProviderRegistry.userFacing,
        store: any ProviderCustomizationStoring = UserDefaultsProviderCustomizationStore()
    ) {
        self.registry = registry
        self.store = store
        items = Self.makeItems(registry: registry, preferences: store.load())
        persist()
    }

    func setVisible(_ isVisible: Bool, for providerID: ProviderID) {
        guard let index = items.firstIndex(where: { $0.id == providerID }) else { return }
        items[index].isVisible = isVisible
        persist()
    }

    @discardableResult
    func moveUp(_ providerID: ProviderID) -> Int? {
        guard let index = items.firstIndex(where: { $0.id == providerID }), index > 0 else {
            return nil
        }
        items.swapAt(index, index - 1)
        persist()
        return index - 1
    }

    @discardableResult
    func moveDown(_ providerID: ProviderID) -> Int? {
        guard
            let index = items.firstIndex(where: { $0.id == providerID }),
            index + 1 < items.count
        else {
            return nil
        }
        items.swapAt(index, index + 1)
        persist()
        return index + 1
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: offsets, toOffset: destination)
        persist()
    }

    @discardableResult
    func move(_ providerID: ProviderID, to destinationID: ProviderID) -> Bool {
        guard
            providerID != destinationID,
            let sourceIndex = items.firstIndex(where: { $0.id == providerID }),
            let destinationIndex = items.firstIndex(where: { $0.id == destinationID })
        else { return false }

        let item = items.remove(at: sourceIndex)
        let insertionIndex = min(destinationIndex, items.count)
        items.insert(item, at: insertionIndex)
        persist()
        return true
    }

    func reset() {
        items = Self.makeItems(registry: registry, preferences: nil)
        persist()
    }

    private func persist() {
        store.save(
            ProviderCustomizationPreferences(
                order: items.map(\.id),
                hidden: Set(items.filter { !$0.isVisible }.map(\.id))
            )
        )
    }

    private static func makeItems(
        registry: [ProviderMetadata],
        preferences: ProviderCustomizationPreferences?
    ) -> [Item] {
        let metadataByID = Dictionary(uniqueKeysWithValues: registry.map { ($0.id, $0) })
        let hidden = preferences?.hidden ?? []
        let previouslyKnown = Set(preferences?.order ?? [])
        var seen: Set<ProviderID> = []
        var ordered: [ProviderMetadata] = []

        for providerID in preferences?.order ?? [] {
            guard seen.insert(providerID).inserted, let metadata = metadataByID[providerID] else {
                continue
            }
            ordered.append(metadata)
        }
        ordered.append(contentsOf: registry.filter { seen.insert($0.id).inserted })

        return ordered.map { metadata in
            let isVisible = if previouslyKnown.contains(metadata.id) {
                !hidden.contains(metadata.id)
            } else {
                metadata.isVisibleByDefault
            }
            return Item(metadata: metadata, isVisible: isVisible)
        }
    }
}
