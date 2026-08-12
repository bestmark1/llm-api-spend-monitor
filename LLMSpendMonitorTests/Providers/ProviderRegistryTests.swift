import AppKit
import XCTest
@testable import LLMSpendMonitor

final class ProviderRegistryTests: XCTestCase {
    func testRegistryContainsSupportedAndOptionalProviders() {
        XCTAssertEqual(
            ProviderRegistry.all.map(\.id),
            [
                .openAI, .anthropic, .gemini, .deepSeek,
                .kimi, .qwen, .xAI, .mistral, .openRouter, .perplexity
            ]
        )
        XCTAssertEqual(Set(ProviderRegistry.all.map(\.id)).count, 10)
        XCTAssertEqual(
            ProviderRegistry.all.filter(\.isVisibleByDefault).map(\.id),
            [.openAI, .anthropic, .gemini, .deepSeek]
        )
        XCTAssertEqual(
            ProviderRegistry.all.filter { $0.integrationAvailability == .available }.map(\.id),
            [.openAI, .anthropic, .gemini, .deepSeek, .qwen]
        )
        XCTAssertEqual(
            ProviderRegistry.userFacing.map(\.id),
            [.openAI, .anthropic, .deepSeek, .kimi, .qwen, .xAI, .mistral, .openRouter, .perplexity]
        )
    }

    func testProviderCapabilitiesReflectOnlyOfficialBasicKeyData() throws {
        let openAI = try XCTUnwrap(ProviderRegistry.metadata(for: .openAI))
        let anthropic = try XCTUnwrap(ProviderRegistry.metadata(for: .anthropic))
        let gemini = try XCTUnwrap(ProviderRegistry.metadata(for: .gemini))
        let deepSeek = try XCTUnwrap(ProviderRegistry.metadata(for: .deepSeek))
        let qwen = try XCTUnwrap(ProviderRegistry.metadata(for: .qwen))

        XCTAssertEqual(openAI.capabilities, [.officialCostHistory, .tokenUsage, .modelBreakdown])
        XCTAssertEqual(anthropic.capabilities, [.officialCostHistory, .tokenUsage, .modelBreakdown])
        XCTAssertEqual(gemini.capabilities, [.credentialValidation, .tokenUsage, .modelBreakdown])
        XCTAssertEqual(deepSeek.capabilities, [.balance])
        XCTAssertEqual(qwen.capabilities, [.balance, .credentialValidation, .officialCostHistory])
    }

    func testOptionalProvidersDoNotClaimUnavailableCapabilities() {
        let optionalProviders = ProviderRegistry.all.filter {
            $0.integrationAvailability == .planned
        }

        XCTAssertEqual(
            optionalProviders.map(\.id),
            [.kimi, .xAI, .mistral, .openRouter, .perplexity]
        )
        XCTAssertTrue(optionalProviders.allSatisfy { $0.capabilities.isEmpty })
        XCTAssertTrue(optionalProviders.allSatisfy { !$0.isVisibleByDefault })
    }

    func testExternalLinksAreTypedAndHTTPS() {
        for provider in ProviderRegistry.all {
            XCTAssertFalse(provider.externalLinks.isEmpty)
            XCTAssertEqual(Set(provider.externalLinks.map(\.kind)).count, provider.externalLinks.count)
            XCTAssertTrue(provider.externalLinks.allSatisfy { $0.url.scheme == "https" })
            XCTAssertNotNil(
                NSImage(systemSymbolName: provider.systemImageName, accessibilityDescription: nil),
                "\(provider.systemImageName) must be a valid SF Symbol"
            )
        }
    }
}
