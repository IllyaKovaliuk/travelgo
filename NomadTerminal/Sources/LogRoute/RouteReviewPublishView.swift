import SwiftUI

/// 16 · Log a route — review & publish. "Publish" is real: it inserts a
/// row in `routes` under the current session and shows the result.
struct RouteReviewPublishView: View {
    let draft: NewRouteDraft
    var onDone: () -> Void

    @State private var visibility: String = "public"
    @State private var isPublishing = false
    @State private var errorMessage: String?
    @State private var published: Route?

    private var distance: Double { Double(draft.distanceKM.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    stepHeader

                    ZStack(alignment: .bottomLeading) {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LinearGradient(colors: [NTColor.pineRaised, NTColor.pineShadow], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(height: 150)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(draft.title.isEmpty ? "Untitled route" : draft.title)
                                .font(NTFont.heading(22, .extraBold))
                            Text(draft.place.isEmpty ? "UNKNOWN REGION" : draft.place.uppercased())
                                .font(NTFont.mono(10.5, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.6))
                        }
                        .padding(16)
                    }
                    .padding(.top, 20)

                    HStack(spacing: 8) {
                        tag(draft.difficulty.rawValue, filled: draft.difficulty.color)
                        tag(draft.transport.rawValue, filled: nil)
                        tag(String(format: "%.1f KM", distance), filled: nil)
                    }
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("VISIBILITY").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                        HStack(spacing: 4) {
                            visButton("Public", "public")
                            visButton("Followers", "followers")
                            visButton("Private", "private")
                        }
                        .padding(4)
                        .background(Capsule().fill(NTColor.milk(0.08)))
                    }
                    .padding(.top, 26)

                    if let errorMessage {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(hex: 0xE58272))
                            Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.milk(0.85))
                        }
                        .padding(16)
                        .background(Color(hex: 0xB33A2B).opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 20)
                    }

                    if let published {
                        HStack(spacing: 10) {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(NTColor.sage)
                            Text("Published — live at ID \(published.id.prefix(8))…").font(NTFont.body(12.5, .medium))
                        }
                        .padding(16)
                        .background(NTColor.sage.opacity(0.15), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                if published != nil {
                    NTPrimaryButton(title: "Done", action: onDone)
                } else {
                    Button(action: publish) {
                        HStack(spacing: 9) {
                            if isPublishing {
                                ProgressView().tint(Color(hex: 0x231007))
                            } else {
                                Text("Publish route").font(NTFont.body(15, .semibold))
                                Image(systemName: "arrow.right")
                            }
                        }
                        .foregroundStyle(Color(hex: 0x231007))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(NTColor.accent, in: Capsule())
                        .shadow(color: NTColor.accent.opacity(0.5), radius: 14, y: 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPublishing)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 14)
            .background(NTColor.pine)
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Review & publish").font(NTFont.body(15, .semibold))
                Spacer()
                Text("3 OF 3").font(NTFont.mono(10, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.5))
            }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(NTColor.milk).frame(height: 3) }
            }
        }
    }

    private func tag(_ text: String, filled: Color?) -> some View {
        Text(text)
            .font(NTFont.mono(11, .semibold)).tracking(0.5)
            .foregroundStyle(filled != nil ? NTColor.milk : NTColor.milk(0.8))
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Capsule().fill(filled ?? .clear))
            .overlay(Capsule().stroke(NTColor.milk(0.26), lineWidth: filled == nil ? 1 : 0))
    }

    private func visButton(_ label: String, _ value: String) -> some View {
        Button { visibility = value } label: {
            Text(label)
                .font(NTFont.body(12.5, .semibold))
                .foregroundStyle(visibility == value ? NTColor.pine : NTColor.milk(0.65))
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Capsule().fill(visibility == value ? NTColor.milk : .clear))
        }
        .buttonStyle(.plain)
    }

    private func publish() {
        isPublishing = true
        errorMessage = nil
        Task {
            do {
                let route = try await RouteRepository.shared.publishRoute(.init(
                    title: draft.title.isEmpty ? "Untitled route" : draft.title,
                    place: draft.place.isEmpty ? "Unknown region" : draft.place,
                    difficulty: draft.difficulty.dbKey,
                    transport: draft.transport.dbKey,
                    transportLabel: draft.transport.rawValue,
                    distanceKM: distance,
                    ascentM: Int(draft.ascentM.rounded()),
                    trackPoints: draft.trackPoints
                ))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { published = route }
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = "Couldn't publish — check your connection and try again."
            }
            isPublishing = false
        }
    }

}
