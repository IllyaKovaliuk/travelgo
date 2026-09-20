import SwiftUI

/// 17 · SOS — hold-to-send emergency beacon.
struct SOSView: View {
    var onClose: () -> Void
    /// Fired the instant the hold gesture completes — flips the Dynamic
    /// Island / lock-screen Live Activity into SOS mode (see
    /// `LiveActivityManager.triggerSOS`). Defaults to a no-op so existing
    /// call sites don't need to change.
    var onTriggered: () -> Void = {}
    /// Fired when leaving this screen — ends or reverts the island's SOS
    /// state. Safe to call even if SOS was never actually triggered.
    var onCancelled: () -> Void = {}

    @State private var holdProgress: CGFloat = 0
    @State private var isSent = false
    @State private var holdTimer: Timer?

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                Spacer()
                dial
                Spacer()
                willSendCard
                contactsRow
                cancelButton
            }
            .padding(.bottom, 14)
        }
        .foregroundStyle(NTColor.milk)
    }

    private var background: some View {
        ZStack {
            Color(hex: 0x1A0A07).ignoresSafeArea()
            Circle().fill(RadialGradient(colors: [Color(hex: 0xB33A2B).opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 280))
                .frame(width: 560, height: 560)
                .position(x: 60, y: 40)
                .ignoresSafeArea()
            Circle().fill(RadialGradient(colors: [Color(hex: 0xB33A2B).opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 240))
                .frame(width: 480, height: 480)
                .position(x: 360, y: 780)
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack {
            Text("NO CELLULAR · GPS ONLY")
                .font(NTFont.mono(10, .medium)).tracking(1.6).foregroundStyle(NTColor.milk(0.5))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    private var dial: some View {
        VStack(spacing: 22) {
            if !isSent {
                Text("Emergency\nbeacon")
                    .font(NTFont.heading(30, .extraBold))
                    .multilineTextAlignment(.center)
            }

            ZStack {
                Circle().stroke(Color(hex: 0xE58272).opacity(0.3), lineWidth: 1.5).frame(width: 220, height: 220)
                Circle().stroke(Color(hex: 0xE58272).opacity(0.16), lineWidth: 1).frame(width: 252, height: 252)

                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color(hex: 0xE58272), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 236, height: 236)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(RadialGradient(colors: [Color(hex: 0xD24C36), Color(hex: 0x7C1405)], center: UnitPoint(x: 0.4, y: 0.32), startRadius: 0, endRadius: 100))
                    .frame(width: 192, height: 192)
                    .scaleEffect(isSent ? 1.05 : (1 - holdProgress * 0.04))

                VStack(spacing: 6) {
                    if isSent {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 22))
                    }
                    Text(isSent ? "SENT" : "SOS")
                        .font(NTFont.heading(isSent ? 22 : 30, .extraBold))
                        .tracking(0.4)
                    Text(isSent ? "HELP IS ON THE WAY" : "HOLD TO SEND")
                        .font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.75))
                }
            }
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startHold() }
                    .onEnded { _ in cancelHold() }
            )
        }
    }

    private var willSendCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WILL SEND").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
            Text("Your last known position, route name and battery level to your emergency contacts and local rescue where covered.")
                .font(NTFont.body(13, .medium))
                .foregroundStyle(NTColor.milk(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(NTColor.milk(0.06), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    private var contactsRow: some View {
        HStack(spacing: 10) {
            ZStack {
                LinearGradient(colors: [NTColor.water, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text("GK").font(NTFont.mono(11, .semibold)).foregroundStyle(NTColor.milk)
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
            Text("Giorgi K. and 1 more will be notified")
                .font(NTFont.body(12.5, .medium))
                .foregroundStyle(NTColor.milk(0.7))
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var cancelButton: some View {
        Button(action: {
            onCancelled()
            onClose()
        }) {
            Text("Cancel")
                .font(NTFont.body(14, .semibold))
                .foregroundStyle(NTColor.milk(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .overlay(Capsule().stroke(NTColor.milk(0.25), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private func startHold() {
        guard holdTimer == nil, !isSent else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            holdProgress = min(1, holdProgress + 0.03 / 2.4)
            if holdProgress >= 1 {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                withAnimation(NTMotion.spring) { isSent = true }
                onTriggered()
                holdTimer?.invalidate()
                holdTimer = nil
            }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        if !isSent {
            withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
        }
    }
}
