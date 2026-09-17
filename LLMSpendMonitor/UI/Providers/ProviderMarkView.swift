import AppKit
import SwiftUI

/// The provider's own mark, tinted and set in the app's tile.
///
/// Marks come from the Simple Icons set (CC0-1.0) as single-colour glyphs and
/// are rendered as templates, so the shape is the provider's and the treatment
/// is Spender's. A provider without a bundled mark — xAI, for one — keeps its
/// SF Symbol, so the row never loses its icon.
struct ProviderMarkView: View {
    let metadata: ProviderMetadata
    var size: CGFloat = 30
    var glyph: CGFloat = 16

    private var tint: Color { ProviderVisualStyle.color(for: metadata.id) }

    var body: some View {
        mark
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(
                tint.opacity(0.12),
                in: RoundedRectangle(cornerRadius: size / 3.75, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var mark: some View {
        if let assetName = metadata.markAssetName, NSImage(named: assetName) != nil {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: glyph, height: glyph)
        } else {
            Image(systemName: metadata.systemImageName)
                .font(.system(size: glyph, weight: .semibold))
        }
    }
}
