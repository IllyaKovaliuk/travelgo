import SwiftUI

/// Real results for the current filter set — presented from Search's
/// "Show results" button.
struct SearchResultsView: View {
    let routes: [Route]
    var onClose: () -> Void

    @State private var openRoute: Route?

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 14) {
                        Button(action: onClose) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(NTColor.milk(0.08)))
                                .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        Text("\(routes.count) routes match")
                            .font(NTFont.heading(20, .bold))
                    }

                    if routes.isEmpty {
                        emptyState.padding(.top, 70)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                            ForEach(routes) { route in
                                tile(route).onTapGesture { openRoute = route }
                            }
                        }
                        .padding(.top, 22)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
        }
        .foregroundStyle(NTColor.milk)
        .fullScreenCover(item: $openRoute) { route in
            RouteDetailFlow(route: route)
        }
    }

    private func tile(_ route: Route) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            RouteCoverImage(url: route.coverImageUrl, tint: NTColor.pineRaised)
                .frame(height: 120)
            VStack(alignment: .leading, spacing: 8) {
                Text(route.title.replacingOccurrences(of: "\n", with: " "))
                    .font(NTFont.heading(14, .bold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(route.difficulty.rawValue)
                        .font(NTFont.mono(9, .semibold))
                        .foregroundStyle(route.difficulty == .moderate ? Color(hex: 0x2B1B05) : NTColor.milk)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(route.difficulty.color))
                    Text(String(format: "%.1f KM", route.distanceKM))
                        .font(NTFont.mono(9.5, .medium))
                        .foregroundStyle(NTColor.milk(0.55))
                }
            }
            .padding(12)
        }
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(NTColor.milk(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(NTColor.milk(0.4))
            Text("No routes match those filters")
                .font(NTFont.heading(19, .bold))
            Text("Try widening distance or dropping a requirement.")
                .font(NTFont.body(13, .light))
                .foregroundStyle(NTColor.milk(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}
