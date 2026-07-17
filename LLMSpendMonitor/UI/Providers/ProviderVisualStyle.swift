import SwiftUI

enum ProviderVisualStyle {
    static func color(for providerID: ProviderID) -> Color {
        switch providerID {
        case .openAI: .teal
        case .anthropic: .orange
        case .gemini: .blue
        case .deepSeek: .indigo
        }
    }
}
