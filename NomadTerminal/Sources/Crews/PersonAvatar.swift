import SwiftUI

/// A roster avatar: the person's photo when they have one, initials otherwise.
struct PersonAvatar: View {
    let person: CrewPerson
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let urlString = person.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        ZStack {
            Circle().fill(NTColor.milk(0.12))
            Text(person.initials)
                .font(NTFont.mono(size * 0.3, .semibold))
                .foregroundStyle(NTColor.milk(0.8))
        }
    }
}
