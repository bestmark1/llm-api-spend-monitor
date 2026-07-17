import XCTest
@testable import LLMSpendMonitor

final class ProviderRegistryTests: XCTestCase {
    func testRegistryContainsExactlyFourStableProviders() {
        XCTAssertEqual(ProviderRegistry.all.map(\.id), [.openAI, .anthropic, .gemini, .deepSeek])
        XCTAssertEqual(Set(ProviderRegistry.all.map(\.id)).count, 4)
    }

    func testProviderCapabilitiesReflectOnlyOfficialBasicKeyData() throws {
        let openAI = try XCTUnwrap(ProviderRegistry.metadata(for: .openAI))
        let anthropic = try XCTUnwrap(ProviderRegistry.metadata(for: .anthropic))
        let gemini = try XCTUnwrap(ProviderRegistry.metadata(for: .gemini))
        let deepSeek = try XCTUnwrap(ProviderRegistry.metadata(for: .deepSeek))

        XCTAssertEqual(openAI.capabilities, [.officialCostHistory, .tokenUsage, .modelBreakdown])
        XCTAssertEqual(anthropic.capabilities, [.officialCostHistory, .tokenUsage, .modelBreakdown])
        XCTAssertEqual(gemini.capabilities, [.credentialValidation])
        XCTAssertEqual(deepSeek.capabilities, [.balance])
    }

    func testExternalLinksAreTypedAndHTTPS() {
        for provider in ProviderRegistry.all {
            XCTAssertFalse(provider.externalLinks.isEmpty)
            XCTAssertEqual(Set(provider.externalLinks.map(\.kind)).count, provider.externalLinks.count)
            XCTAssertTrue(provider.externalLinks.allSatisfy { $0.url.scheme == "https" })
        }
    }
}
