import SwiftUI

/// "Invite to <crew>": the code in cells, Copy / Share, and how long it lasts.
/// Any member may invite; resetting the code revokes the old one (managers) and
/// makes a new one. Sharing is counted for the invite funnel only when the
/// share sheet reports it completed.
struct InviteSheet: View {
    let crewId: UUID
    let crewName: String
    var onClose: () -> Void

    enum Expiry: Int, CaseIterable {
        case day = 1, week = 7, month = 30
        var title: String {
            switch self {
            case .day: return String(localized: "24 hours")
            case .week: return String(localized: "7 days")
            case .month: return String(localized: "30 days")
            }
        }
    }

    @State private var expiry: Expiry = .week
    @State private var code: String?
    @State private var expiresAt: Date?
    @State private var isWorking = false
    @State private var copied = false
    @State private var showShare = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    MonoLabel("Invite to")
                    Text(crewName).font(NTFont.heading(26, .extraBold)).tracking(-0.6).lineLimit(2)
                }
                Spacer()
                CircleIconButton(icon: "xmark", label: "Close", filled: true, action: onClose)
            }

            codeCard

            HStack(spacing: 12) {
                Button { copy() } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(NTFont.body(16, .semibold)).foregroundStyle(NTColor.pine)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(NTColor.milk, in: Capsule())
                }
                .buttonStyle(.plain).disabled(code == nil)
                Button { showShare = true } label: {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .font(NTFont.body(16, .semibold)).foregroundStyle(Color(hex: 0x231007))
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(NTColor.accent, in: Capsule())
                        .shadow(color: NTColor.accent.opacity(0.45), radius: 14, y: 8)
                }
                .buttonStyle(.plain).disabled(code == nil)
            }

            VStack(alignment: .leading, spacing: 8) {
                MonoLabel("Code expires after")
                CrewSegments(items: Expiry.allCases.map { ($0, $0.title) }, selection: $expiry)
                    .disabled(isWorking)
            }

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(NTColor.gold)
                Text("Anyone with this code can join and see the crew's expeditions, routes and member names. Share it only with people you'd hike with.")
                    .font(NTFont.body(13.5)).foregroundStyle(NTColor.milk(0.85))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NTColor.pineRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            if let errorMessage {
                Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
            }

            Button { Task { await make(revokeOld: true) } } label: {
                Text("Reset code").font(NTFont.body(14, .semibold)).underline().foregroundStyle(NTColor.milk)
                    .frame(maxWidth: .infinity).frame(height: 44)
            }
            .buttonStyle(.plain).disabled(isWorking)
        }
        .padding(.horizontal, 16).padding(.top, 22).padding(.bottom, 10)
        .background(NTColor.pineElevated.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .task { if code == nil { await make(revokeOld: false) } }
        .onChange(of: expiry) { _, _ in Task { await make(revokeOld: true) } }
        .sheet(isPresented: $showShare) {
            if let code {
                ActivityView(items: [String(localized: "Join my crew on Nomad: \(CrewLinks.url(forInviteCode: code).absoluteString)")]) { completed, activity in
                    guard completed else { return }
                    RouteRepository.shared.logEvent("crew_invite_sent", metadata: [
                        "crew_id": crewId.uuidString, "channel": activity ?? "unknown",
                    ])
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var codeCard: some View {
        VStack(spacing: 14) {
            if let code {
                let groups = stride(from: 0, to: code.count, by: 4).map { i -> String in
                    let a = code.index(code.startIndex, offsetBy: i)
                    let b = code.index(a, offsetBy: min(4, code.count - i))
                    return String(code[a..<b]).uppercased()
                }
                HStack(spacing: 6) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { i, g in
                        if i > 0 { Text("–").foregroundStyle(NTColor.milk(0.35)) }
                        Text(g)
                            .font(NTFont.mono(19, .semibold)).tracking(1)
                            .padding(.horizontal, 8).frame(height: 46)
                            .background(NTColor.pineRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(NTColor.pineLine, lineWidth: 1))
                    }
                }
                .minimumScaleFactor(0.6).lineLimit(1)
                if let expiresAt {
                    Text("EXPIRES \(expiresAt.formatted(.dateTime.day(.twoDigits).month(.abbreviated).hour().minute()).uppercased())")
                        .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                }
            } else {
                ProgressView().tint(NTColor.milk).frame(height: 70)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18).padding(.horizontal, 10)
        .background(NTColor.pine, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.pineLine, lineWidth: 1))
    }

    private func copy() {
        guard let code else { return }
        UIPasteboard.general.string = CrewLinks.url(forInviteCode: code).absoluteString
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        copied = true
        Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
    }

    private func make(revokeOld: Bool) async {
        isWorking = true
        errorMessage = nil
        let old = code
        do {
            let new = try await CrewRepository.shared.createInvite(crewId: crewId, ttlDays: expiry.rawValue)
            code = new
            expiresAt = Calendar.current.date(byAdding: .day, value: expiry.rawValue, to: Date())
            if revokeOld, let old { try? await CrewRepository.shared.revokeInvite(code: old) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }
}
