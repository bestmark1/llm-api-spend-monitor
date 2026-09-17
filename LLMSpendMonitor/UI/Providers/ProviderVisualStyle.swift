import AppKit
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
        // xAI's mark is monochrome, and monochrome is also the safest slot left in a
        // palette this full: it separates by lightness instead of hue, so it can never
        // read as a twin of another provider. It has to invert per appearance —
        // ink on the light card measures above 3:1, while the same ink on the dark
        // card drops to 1.62:1 and reads as a hole in the ring.
        case .xAI: .providerInk
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

private extension Color {
    static let providerInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            // Held back from pure white: at full brightness the monochrome segment
            // outshouts every hue beside it. #E8E8ED is the dimmest step at which xAI
            // still is not the palette's limiting pair for colour vision.
            ? NSColor(srgbRed: 0.910, green: 0.910, blue: 0.929, alpha: 1)
            : NSColor(srgbRed: 0.110, green: 0.110, blue: 0.118, alpha: 1)
    })
}
