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
            [.openAI, .anthropic, .deepSeek]
        )
        XCTAssertEqual(
            ProviderRegistry.all.filter { $0.integrationAvailability == .available }.map(\.id),
            [.openAI, .anthropic, .gemini, .deepSeek, .kimi, .qwen, .xAI, .mistral, .openRouter]
        )
        XCTAssertEqual(
            ProviderRegistry.userFacing.map(\.id),
            [.openAI, .anthropic, .deepSeek, .kimi, .qwen, .xAI, .mistral, .openRouter]
        )
    }

    func testProviderCapabilitiesReflectOnlyOfficialBasicKeyData() throws {
        let openAI = try XCTUnwrap(ProviderRegistry.metadata(for: .openAI))
        let anthropic = try XCTUnwrap(ProviderRegistry.metadata(for: .anthropic))
        let gemini = try XCTUnwrap(ProviderRegistry.metadata(for: .gemini))
        let deepSeek = try XCTUnwrap(ProviderRegistry.metadata(for: .deepSeek))
        let kimi = try XCTUnwrap(ProviderRegistry.metadata(for: .kimi))
        let qwen = try XCTUnwrap(ProviderRegistry.metadata(for: .qwen))
        let xAI = try XCTUnwrap(ProviderRegistry.metadata(for: .xAI))
        let mistral = try XCTUnwrap(ProviderRegistry.metadata(for: .mistral))
        let openRouter = try XCTUnwrap(ProviderRegistry.metadata(for: .openRouter))

        XCTAssertEqual(openAI.capabilities, [.officialCostHistory, .tokenUsage, .modelBreakdown])
        XCTAssertEqual(anthropic.capabilities, [.officialCostHistory, .tokenUsage, .modelBreakdown])
        XCTAssertEqual(gemini.capabilities, [.credentialValidation, .tokenUsage, .modelBreakdown])
        XCTAssertEqual(deepSeek.capabilities, [.balance, .estimatedCostHistory])
        XCTAssertEqual(kimi.capabilities, [.balance])
        XCTAssertEqual(qwen.capabilities, [.balance, .credentialValidation, .officialCostHistory])
        XCTAssertEqual(xAI.capabilities, [.balance, .officialCostHistory, .modelBreakdown])
        XCTAssertEqual(mistral.capabilities, [.balance])
        XCTAssertEqual(openRouter.capabilities, [.balance])
    }

    func testNoProviderStillPromisesAPlannedIntegration() {
        XCTAssertTrue(ProviderRegistry.all.allSatisfy {
            $0.integrationAvailability != .planned
        })
    }

    func testPerplexityExplainsMissingAccountWideFinancialAPI() throws {
        let unavailableProviders = ProviderRegistry.all.filter {
            $0.integrationAvailability == .unavailable
        }

        XCTAssertEqual(unavailableProviders.map(\.id), [.perplexity])
        let perplexity = try XCTUnwrap(unavailableProviders.first)
        XCTAssertTrue(perplexity.capabilities.isEmpty)
        XCTAssertFalse(perplexity.isVisibleByDefault)
        XCTAssertTrue(perplexity.credentialHelp.contains("account-wide"))
        XCTAssertTrue(perplexity.credentialHelp.contains("public API"))
    }

    func testUnavailableProvidersDoNotClaimUnavailableCapabilities() {
        let unavailableProviders = ProviderRegistry.all.filter {
            $0.integrationAvailability == .unavailable
        }

        XCTAssertTrue(unavailableProviders.allSatisfy { $0.capabilities.isEmpty })
        XCTAssertTrue(unavailableProviders.allSatisfy { !$0.isVisibleByDefault })
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
