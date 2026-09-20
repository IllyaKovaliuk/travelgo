import SwiftUI

/// One category's situations, as expandable cards — tap a situation to
/// read the guidance, matching the disclosure-card pattern used elsewhere
/// in the app (Search's filter sections).
struct GuideCategoryDetailView: View {
    let category: GuideCategory

    @State private var expanded: Set<UUID> = []

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                header

                ForEach(category.situations) { situation in
                    situationCard(situation)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let first = category.situations.first { expanded.insert(first.id) }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(category.tint.opacity(0.2))
                Image(systemName: category.icon).font(.system(size: 22)).foregroundStyle(category.tint)
            }
            .frame(width: 56, height: 56)
            Text(category.title)
                .font(NTFont.heading(24, .extraBold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 6)
    }

    private func situationCard(_ situation: GuideSituation) -> some View {
        let isOpen = expanded.contains(situation.id)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(NTMotion.spring) {
                    if isOpen { expanded.remove(situation.id) } else { expanded.insert(situation.id) }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(situation.title)
                        .font(NTFont.heading(15.5, .bold))
                        .foregroundStyle(NTColor.milk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NTColor.milk(0.5))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(situation.body)
                    .font(NTFont.body(14, .light))
                    .foregroundStyle(NTColor.milk(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
        .padding(18)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(category.tint.opacity(isOpen ? 0.4 : 0.12), lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        GuideCategoryDetailView(category: GuideCategory.all[0])
    }
}
