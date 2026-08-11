import XCTest
@testable import LLMSpendMonitor

@MainActor
final class CustomizeViewModelTests: XCTestCase {
    func testDefaultsToRegistryOrderWithOnlyAvailableProvidersVisible() {
        let model = CustomizeViewModel(store: InMemoryCustomizationStore())

        XCTAssertEqual(model.items.map(\.id), ProviderRegistry.all.map(\.id))
        XCTAssertEqual(
            model.visibleProviderIDs,
            [.openAI, .anthropic, .gemini, .deepSeek]
        )
    }

    func testVisibilityAndOrderPersistAcrossRelaunch() {
        let store = InMemoryCustomizationStore()
        let model = CustomizeViewModel(store: store)

        model.setVisible(false, for: .gemini)
        XCTAssertEqual(model.moveUp(.deepSeek), 2)
        XCTAssertEqual(model.moveUp(.deepSeek), 1)

        let relaunched = CustomizeViewModel(store: store)
        var expectedOrder = ProviderRegistry.all.map(\.id)
        expectedOrder.removeAll { $0 == .deepSeek }
        expectedOrder.insert(.deepSeek, at: 1)

        XCTAssertEqual(relaunched.items.map(\.id), expectedOrder)
        XCTAssertEqual(relaunched.visibleProviderIDs, [.openAI, .deepSeek, .anthropic])
        XCTAssertFalse(relaunched.items.first { $0.id == .gemini }!.isVisible)
    }

    func testPlannedProviderCanBeShownAndAvailableGeminiCanBeHidden() {
        let store = InMemoryCustomizationStore()
        let model = CustomizeViewModel(store: store)

        model.setVisible(false, for: .gemini)
        model.setVisible(true, for: .kimi)

        let relaunched = CustomizeViewModel(store: store)
        XCTAssertFalse(relaunched.items.first { $0.id == .gemini }!.isVisible)
        XCTAssertTrue(relaunched.items.first { $0.id == .kimi }!.isVisible)
        XCTAssertEqual(
            relaunched.visibleProviderIDs,
            [.openAI, .anthropic, .deepSeek, .kimi]
        )
    }

    func testStoredPreferencesAreReconciledWhenProvidersChange() {
        let store = InMemoryCustomizationStore(
            preferences: ProviderCustomizationPreferences(
                order: [.gemini, .gemini, .openAI],
                hidden: [.gemini]
            )
        )

        let model = CustomizeViewModel(store: store)
        let remainingProviders = ProviderRegistry.all.map(\.id).filter {
            $0 != .gemini && $0 != .openAI
        }

        XCTAssertEqual(model.items.map(\.id), [.gemini, .openAI] + remainingProviders)
        XCTAssertEqual(Set(model.items.map(\.id)), Set(ProviderID.allCases))
        XCTAssertEqual(model.visibleProviderIDs, [.openAI, .anthropic, .deepSeek])
    }

    func testMoveBoundariesAndResetAreDeterministic() {
        let model = CustomizeViewModel(store: InMemoryCustomizationStore())

        XCTAssertNil(model.moveUp(.openAI))
        XCTAssertNil(model.moveDown(.perplexity))
        XCTAssertEqual(model.moveDown(.openAI), 1)
        var expectedOrder = ProviderRegistry.all.map(\.id)
        expectedOrder.swapAt(0, 1)
        XCTAssertEqual(model.items.map(\.id), expectedOrder)

        model.setVisible(false, for: .anthropic)
        model.reset()

        XCTAssertEqual(model.items.map(\.id), ProviderRegistry.all.map(\.id))
        XCTAssertEqual(
            model.visibleProviderIDs,
            [.openAI, .anthropic, .gemini, .deepSeek]
        )
    }
}

private final class InMemoryCustomizationStore: ProviderCustomizationStoring {
    private var preferences: ProviderCustomizationPreferences?

    init(preferences: ProviderCustomizationPreferences? = nil) {
        self.preferences = preferences
    }

    func load() -> ProviderCustomizationPreferences? {
        preferences
    }

    func save(_ preferences: ProviderCustomizationPreferences) {
        self.preferences = preferences
    }
}
