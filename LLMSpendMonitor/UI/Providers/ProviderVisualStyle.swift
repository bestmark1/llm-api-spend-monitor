import SwiftUI

enum ProviderVisualStyle {
    static func color(for providerID: ProviderID) -> Color {
        switch providerID {
        case .openAI: .teal
        case .anthropic: .orange
        case .gemini: .blue
        case .deepSeek: .indigo
        case .kimi: .pink
        case .qwen: .purple
        case .xAI: .gray
        case .mistral: .red
        case .openRouter: .mint
        case .perplexity: .cyan
        }
    }
}
