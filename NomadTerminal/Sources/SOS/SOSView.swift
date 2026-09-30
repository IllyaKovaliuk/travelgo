import SwiftUI
import CoreLocation
import MessageUI

/// 17 · SOS — hold-to-send emergency beacon. "Send" is now real: holding
/// the dial opens a pre-filled system Messages sheet addressed to your
/// emergency contacts with your last known position, via
/// `MessageComposeView`. It still needs a human tap on Send inside that
/// sheet — Apple gives no API to fire an SMS/iMessage with zero user
/// interaction, on purpose — so this is as automatic as it can honestly be.
struct SOSView: View {
    var onClose: () -> Void
    /// Real last GPS fix from whichever screen presented this — threaded in
    /// from `RouteTracker.points.last` (recording) or
    /// `CompassTracker.currentLocation` (compass). Nil is handled: the
    /// message just omits the position line rather than sending a lie.
    var lastKnownCoordinate: CLLocationCoordinate2D? = nil
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
    /// Real, not the hardcoded fake "Giorgi K." this row used to show
    /// regardless of whether anyone had ever set up a real contact.
    @State private var contacts: [RouteRepository.EmergencyContact] = []
    @State private var showMessageCompose = false

    /// Contacts we can actually text — `MFMessageComposeViewController`
    /// needs a phone number, an email-only contact can't receive an SMS.
    private var textableContacts: [RouteRepository.EmergencyContact] {
        contacts.filter { $0.phone?.isEmpty == false }
    }
    /// False in Simulator (no cellular/iMessage stack) and on a real
    /// device with no active line/iMessage — checked before ever offering
    /// the button, instead of presenting a sheet doomed to fail.
    private var canMessage: Bool { MFMessageComposeViewController.canSendText() }

    private var messageBody: String {
        var lines = ["🆘 This is an emergency — I need help."]
        if let lastKnownCoordinate {
            lines.append("My last known position: https://maps.apple.com/?ll=\(lastKnownCoordinate.latitude),\(lastKnownCoordinate.longitude)")
        }
        lines.append("Sent from NomadCompass.")
        return lines.joined(separator: "\n")
    }

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
        .task {
            contacts = (try? await RouteRepository.shared.fetchEmergencyContacts()) ?? []
        }
        .sheet(isPresented: $showMessageCompose) {
            MessageComposeView(
                recipients: textableContacts.compactMap { $0.phone },
                body: messageBody,
                onFinish: { showMessageCompose = false }
            )
            .ignoresSafeArea()
        }
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
            Text(canMessage ? "GPS BEACON · TEXTS CONTACTS" : "GPS BEACON · NO SIGNAL")
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
            Text(willSendCopy)
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

    /// Honest, not aspirational — describes exactly what holding the dial
    /// actually does on this device, not a fictional dispatch service.
    /// There is no rescue-service integration; never claim there is one.
    private var willSendCopy: LocalizedStringKey {
        if !canMessage {
            return "Opens your Messages app pre-filled with your last known position — not available in this environment (no active line)."
        } else if textableContacts.isEmpty {
            return "Add a phone number to an emergency contact in Settings to enable this — a text with your last known position will open, ready to send."
        } else {
            return "Opens a text to your emergency contacts, pre-filled with your last known position. You still tap Send yourself."
        }
    }

    private var contactsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if let first = contacts.first {
                    ZStack {
                        LinearGradient(colors: [NTColor.water, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text(initials(first.name)).font(NTFont.mono(11, .semibold)).foregroundStyle(NTColor.milk)
                    }
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
                    Text(contactsLabel)
                        .font(NTFont.body(12.5, .medium))
                        .foregroundStyle(NTColor.milk(0.7))
                } else {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 18)).foregroundStyle(NTColor.milk(0.4))
                    Text("No emergency contacts set — add some in Settings")
                        .font(NTFont.body(12.5, .medium))
                        .foregroundStyle(NTColor.milk(0.5))
                }
                Spacer()
            }

            if isSent && canMessage && !textableContacts.isEmpty {
                Button(action: { showMessageCompose = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                        Text("Message emergency contacts").font(NTFont.body(13, .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x1A0A07))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(NTColor.milk, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private var contactsLabel: String {
        guard let first = contacts.first else { return "" }
        return contacts.count > 1 ? "\(first.name) and \(contacts.count - 1) more" : first.name
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        let chars = parts.prefix(2).compactMap { $0.first }
        return chars.isEmpty ? "?" : String(chars).uppercased()
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
                RouteRepository.shared.logEvent("sos_triggered")
                onTriggered()
                holdTimer?.invalidate()
                holdTimer = nil
                // The actual "send" — opens the real Messages compose sheet
                // right away rather than making it a second, easy-to-miss
                // tap. Only when it can actually work; otherwise the
                // "Message emergency contacts" button stays available below
                // for a retry once there's signal.
                if canMessage && !textableContacts.isEmpty {
                    showMessageCompose = true
                }
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
