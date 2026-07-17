import XCTest
@testable import LLMSpendMonitor

@MainActor
final class CustomizeViewModelTests: XCTestCase {
    func testDefaultsToRegistryOrderWithEveryProviderVisible() {
        let model = CustomizeViewModel(store: InMemoryCustomizationStore())

        XCTAssertEqual(model.items.map(\.id), ProviderRegistry.all.map(\.id))
        XCTAssertTrue(model.items.allSatisfy(\.isVisible))
        XCTAssertEqual(model.visibleProviderIDs, ProviderRegistry.all.map(\.id))
    }

    func testVisibilityAndOrderPersistAcrossRelaunch() {
        let store = InMemoryCustomizationStore()
        let model = CustomizeViewModel(store: store)

        model.setVisible(false, for: .gemini)
        XCTAssertEqual(model.moveUp(.deepSeek), 2)
        XCTAssertEqual(model.moveUp(.deepSeek), 1)

        let relaunched = CustomizeViewModel(store: store)

        XCTAssertEqual(relaunched.items.map(\.id), [.openAI, .deepSeek, .anthropic, .gemini])
        XCTAssertEqual(relaunched.visibleProviderIDs, [.openAI, .deepSeek, .anthropic])
        XCTAssertFalse(relaunched.items.first { $0.id == .gemini }!.isVisible)
    }

    func testStoredPreferencesAreReconciledWhenProvidersChange() {
        let store = InMemoryCustomizationStore(
            preferences: ProviderCustomizationPreferences(
                order: [.gemini, .gemini, .openAI],
                hidden: [.gemini]
            )
        )

        let model = CustomizeViewModel(store: store)

        XCTAssertEqual(model.items.map(\.id), [.gemini, .openAI, .anthropic, .deepSeek])
        XCTAssertEqual(Set(model.items.map(\.id)), Set(ProviderID.allCases))
        XCTAssertEqual(model.visibleProviderIDs, [.openAI, .anthropic, .deepSeek])
    }

    func testMoveBoundariesAndResetAreDeterministic() {
        let model = CustomizeViewModel(store: InMemoryCustomizationStore())

        XCTAssertNil(model.moveUp(.openAI))
        XCTAssertNil(model.moveDown(.deepSeek))
        XCTAssertEqual(model.moveDown(.openAI), 1)
        XCTAssertEqual(model.items.map(\.id), [.anthropic, .openAI, .gemini, .deepSeek])

        model.setVisible(false, for: .anthropic)
        model.reset()

        XCTAssertEqual(model.items.map(\.id), ProviderRegistry.all.map(\.id))
        XCTAssertTrue(model.items.allSatisfy(\.isVisible))
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
