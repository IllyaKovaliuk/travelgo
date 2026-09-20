import SwiftUI

/// 03 · Onboarding — Permissions
struct PermissionsView: View {
    var onFinished: () -> Void

    @StateObject private var location = LocationPermission()
    @State private var offlineReady = false

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    PageDots(count: 3, index: 2)
                        .revealOnAppear(delay: 0.02)

                    Text("Two things we\nneed out there.")
                        .font(NTFont.heading(34, .extraBold))
                        .foregroundStyle(NTColor.milk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 26)
                        .revealOnAppear(delay: 0.06)

                    VStack(spacing: 18) {
                        PermissionCard(
                            icon: "location.fill",
                            iconTint: NTColor.water,
                            title: "Precise location",
                            description: "Turn-by-turn on unnamed tracks, and an SOS ping that still works with no signal.",
                            buttonLabel: "Allow while using",
                            doneLabel: "Allowed",
                            isDone: location.isGranted,
                            action: location.request
                        )
                        .revealOnAppear(delay: 0.14, distance: 20)

                        PermissionCard(
                            icon: "arrow.down.circle.fill",
                            iconTint: NTColor.gold,
                            title: "Offline storage",
                            description: "Cache tiles, elevation and gear lists so the route survives four days without a bar of service.",
                            buttonLabel: "Allow",
                            doneLabel: "Allowed",
                            isDone: offlineReady,
                            action: { offlineReady = true }
                        )
                        .revealOnAppear(delay: 0.2, distance: 20)
                    }
                    .padding(.top, 30)

                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(NTColor.milk(0.6))
                        Text("You can browse without either. Navigation stays locked.")
                            .font(NTFont.body(13, .light))
                            .foregroundStyle(NTColor.milk(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                            .stroke(NTColor.milk(0.12), lineWidth: 1)
                    )
                    .padding(.top, 26)
                    .revealOnAppear(delay: 0.3)

                    NTGhostButton(title: "Skip for now", action: onFinished)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        .revealOnAppear(delay: 0.34)
                }
                .padding(.horizontal, 30)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
        }
        .onChange(of: location.isGranted) { _, granted in
            if granted { advanceIfReady() }
        }
        .onChange(of: offlineReady) { _, _ in advanceIfReady() }
    }

    private func advanceIfReady() {
        guard location.isGranted, offlineReady else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onFinished()
        }
    }
}

#Preview {
    PermissionsView(onFinished: {})
}
