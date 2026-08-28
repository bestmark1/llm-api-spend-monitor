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

enum GlassProminence {
    case panel
    case primary
    case secondary

    var material: Material {
        switch self {
        case .panel: .ultraThin
        case .primary: .regular
        case .secondary: .thin
        }
    }

    var highlightOpacity: Double {
        switch self {
        case .panel: 0.08
        case .primary: 0.12
        case .secondary: 0.07
        }
    }

    var shadow: (opacity: Double, radius: CGFloat, y: CGFloat) {
        switch self {
        case .panel: (0.18, 18, 8)
        case .primary: (0.13, 10, 5)
        case .secondary: (0.09, 7, 3)
        }
    }
}

struct GlassSurface: View {
    let cornerRadius: CGFloat
    let prominence: GlassProminence
    var isHovered = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let shadow = prominence.shadow

        shape
            .fill(backgroundStyle)
            .overlay {
                if !reduceTransparency {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(prominence.highlightOpacity + (isHovered ? 0.06 : 0)),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(borderOpacity + (isHovered ? 0.12 : 0)),
                            .white.opacity(colorScheme == .dark ? 0.06 : 0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(
                color: .black.opacity(reduceTransparency ? 0.05 : shadow.opacity + (isHovered ? 0.04 : 0)),
                radius: shadow.radius + (isHovered ? 2 : 0),
                y: shadow.y
            )
    }

    private var backgroundStyle: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        }
        return AnyShapeStyle(prominence.material)
    }

    private var borderOpacity: Double {
        colorScheme == .dark ? 0.24 : 0.48
    }
}
