import SwiftUI

/// A route's cover — a real uploaded photo when one exists, the decorative
/// `ImagePlaceholder` otherwise. Every card/tile that shows a route cover
/// should go through this rather than `ImagePlaceholder` directly, so a
/// real photo actually gets used once one exists.
struct RouteCoverImage: View {
    var url: String?
    var caption: String? = nil
    var tint: Color = NTColor.pineRaised

    /// The photo is an overlay on a clear base, so its intrinsic size never
    /// leaks into layout: a wide (or tall) cover used to stretch its card
    /// past the screen edge, because `aspectRatio(.fill)` proposes the
    /// image's own width to the parent. The caller's frame decides the size.
    var body: some View {
        Color.clear
            .overlay { content }
            .clipped()
    }

    @ViewBuilder
    private var content: some View {
        if let url, let imageURL = URL(string: url) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    ImagePlaceholder(caption: caption, tint: tint)
                default:
                    ZStack {
                        ImagePlaceholder(caption: nil, tint: tint)
                        ProgressView().tint(NTColor.milk(0.5))
                    }
                }
            }
        } else {
            ImagePlaceholder(caption: caption, tint: tint)
        }
    }
}
