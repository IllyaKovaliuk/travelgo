import SwiftUI

/// One real author avatar — their actual uploaded photo when
/// `Author.avatarUrl` is set, the existing gradient-initials fallback
/// otherwise. Shared by every place an author shows up (Home's route
/// rows, Route Detail's author row, profile headers) so a real photo,
/// once someone sets one, shows up everywhere consistently instead of
/// needing each call site to remember to check for it.
struct AvatarView: View {
    let author: Author
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let urlString = author.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fallback: some View {
        ZStack {
            LinearGradient(colors: author.gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(author.initials).font(NTFont.heading(size * 0.42, .semibold)).foregroundStyle(.white)
        }
    }
}
