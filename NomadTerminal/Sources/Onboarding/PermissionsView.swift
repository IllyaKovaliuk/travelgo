import SwiftUI

/// 03 · Onboarding — Permissions
struct PermissionsView: View {
    var onFinished: () -> Void

    @StateObject private var location = LocationPermission()

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
                            description: "Live position on the map and your real track while recording — plus a last-known position to send if you ever use SOS.",
                            buttonLabel: "Continue",
                            doneLabel: "Allowed",
                            isDone: location.isGranted,
                            action: location.request
                        )
                        .revealOnAppear(delay: 0.14, distance: 20)
                    }
                    .padding(.top, 30)

                    // There used to be a second "Offline storage" card here
                    // promising cached map tiles, elevation and gear lists —
                    // none of that exists. The real offline cache
                    // (`OfflineRouteStore`) saves a route's own JSON + cover
                    // photo once you've opened it, automatically, with
                    // nothing to "allow" here — so removed the card rather
                    // than ship a button that only flipped a local boolean
                    // and did nothing real.
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(NTColor.milk(0.6))
                        Text("You choose in the next step. If you don't allow it, live position, recording, and SOS position won't work, but the rest of the app does — and you can change this later in Settings.")
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

                }
                .padding(.horizontal, 30)
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
        }
        // Any answer to the system prompt (allow OR deny) moves on — a deny
        // used to leave this screen sitting with a button that did nothing.
        .onChange(of: location.status) { _, status in
            if status != .notDetermined { advance() }
        }
    }

    private func advance() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onFinished()
        }
    }
}

#Preview {
    PermissionsView(onFinished: {})
}
