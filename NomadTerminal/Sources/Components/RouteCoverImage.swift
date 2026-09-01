import SwiftUI

/// A route's cover — a real uploaded photo when one exists, the decorative
/// `ImagePlaceholder` otherwise. Every card/tile that shows a route cover
/// should go through this rather than `ImagePlaceholder` directly, so a
/// real photo actually gets used once one exists.
struct RouteCoverImage: View {
    var url: String?
    var caption: String? = nil
    var tint: Color = NTColor.pineRaised

    var body: some View {
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
