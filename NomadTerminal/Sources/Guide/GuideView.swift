import SwiftUI

/// The Field Guide — practical "what do I do if..." guidance organized by
/// situation. Nomad's whole pitch is a terminal for people going
/// somewhere off-grid; this is the part of that promise that isn't a map.
struct GuideView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var path: [GuideCategory] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    disclaimerBanner

                    LazyVGrid(columns: AdaptiveColumns.grid(spacing: 12, sizeClass: sizeClass), spacing: 12) {
                        ForEach(GuideCategory.all) { category in
                            categoryCard(category)
                                .onTapGesture { path.append(category) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 110)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationDestination(for: GuideCategory.self) { category in
                GuideCategoryDetailView(category: category)
            }
        }
        .tint(NTColor.milk)
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FIELD GUIDE").font(NTFont.mono(10.5, .medium)).tracking(1.4).foregroundStyle(NTColor.milk(0.5))
            Text("What to do out there.")
                .font(NTFont.heading(30, .extraBold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Practical guidance for the situations that actually come up off-grid — not a first-aid manual, just what to do next.")
                .font(NTFont.body(13.5, .light))
                .foregroundStyle(NTColor.milk(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    /// Real, not decorative — this app is not a medical reference or a
    /// rescue service, and the SOS screen it links to is a text message to
    /// your own contacts, not a monitored beacon. Said plainly, once,
    /// where it's actually read rather than buried in a settings footer.
    private var disclaimerBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(NTColor.milk(0.5))
                .padding(.top, 1)
            Text("General guidance, not medical or professional rescue advice. This app's SOS screen texts your own emergency contacts — it's not a satellite beacon and nothing here is monitored. Call local emergency services directly when you can, and carry a dedicated satellite device somewhere beyond cell coverage.")
                .font(NTFont.body(11.5, .medium))
                .foregroundStyle(NTColor.milk(0.6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }

    private func categoryCard(_ category: GuideCategory) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                Circle().fill(category.tint.opacity(0.2))
                Image(systemName: category.icon).font(.system(size: 18)).foregroundStyle(category.tint)
            }
            .frame(width: 44, height: 44)

            Text(category.title)
                .font(NTFont.heading(15, .bold))
                .foregroundStyle(NTColor.milk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(category.situations.count) SITUATIONS")
                .font(NTFont.mono(9, .medium)).tracking(1)
                .foregroundStyle(NTColor.milk(0.45))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
    }
}

extension GuideCategory: Hashable {
    static func == (lhs: GuideCategory, rhs: GuideCategory) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    GuideView()
}
