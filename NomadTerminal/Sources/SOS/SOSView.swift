import SwiftUI
import CoreLocation
import MessageUI

/// 17 · SOS. Holding the dial opens a pre-filled system Messages sheet
/// addressed to your emergency contacts with your last known position, via
/// `MessageComposeView` — that's the entire mechanism. There is no rescue
/// service, no monitored beacon, no dispatch of any kind behind this
/// screen, and the UI must never imply otherwise: "SENT" only appears once
/// `MFMessageComposeViewController` itself reports the message actually
/// went out (`messageResult == .sent`), and "help is on the way" never
/// appears at all — nobody has been notified that anyone needs help until
/// a real contact reads a real text message and decides to act on it.
/// (Previously this screen marked every completed hold as "SENT — HELP IS
/// ON THE WAY" regardless of whether a message sheet even opened, which a
/// field read flagged correctly as a real safety hazard: someone could
/// hold the dial, see "help is on the way," and wait for rescue that was
/// never actually requested.)
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
    /// True once the hold gesture itself completes — says nothing about
    /// whether a message actually sent. Kept separate from `messageResult`
    /// on purpose: this screen must never conflate "you held the dial"
    /// with "help was requested."
    @State private var isTriggered = false
    /// Real outcome from `MFMessageComposeViewController`, nil until it
    /// reports one. Only `.sent` means a message genuinely went out —
    /// `.cancelled`/`.failed` must read as failure, not success.
    @State private var messageResult: MessageComposeResult?
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

    /// What the dial's center actually says — every branch here is real,
    /// not aspirational. Nothing in this screen may claim help is coming;
    /// the honest ceiling is "a message genuinely sent" or "nothing was
    /// sent, here's why."
    private var dialTitle: LocalizedStringKey {
        guard isTriggered else { return "SOS" }
        switch messageResult {
        case .sent: return "SENT"
        case .cancelled, .failed: return "NOT SENT"
        case .none: return canMessage && !textableContacts.isEmpty ? "SOS" : "NO HELP CALLED"
        @unknown default: return "NOT SENT"
        }
    }

    private var dialSubtitle: LocalizedStringKey {
        guard isTriggered else { return "HOLD TO SEND" }
        switch messageResult {
        case .sent: return "MESSAGE SENT TO CONTACTS"
        case .cancelled, .failed: return "TRY AGAIN BELOW"
        case .none:
            if textableContacts.isEmpty { return "ADD CONTACTS IN SETTINGS" }
            if !canMessage { return "NO SIGNAL — CAN'T SEND" }
            return "OPEN MESSAGES BELOW"
        @unknown default: return "TRY AGAIN BELOW"
        }
    }

    private var messageBody: String {
        var lines = ["🆘 This is an emergency — I need help."]
        if let lastKnownCoordinate {
            lines.append("My last known position: https://maps.apple.com/?ll=\(lastKnownCoordinate.latitude),\(lastKnownCoordinate.longitude)")
        }
        lines.append("Sent from Nomad.")
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
            .scrollsWhenShort()
        }
        .foregroundStyle(NTColor.milk)
        .task {
            contacts = (try? await RouteRepository.shared.fetchEmergencyContacts()) ?? []
        }
        .sheet(isPresented: $showMessageCompose) {
            MessageComposeView(
                recipients: textableContacts.compactMap { $0.phone },
                body: messageBody,
                onFinish: { result in
                    showMessageCompose = false
                    messageResult = result
                    // Real outcome, not "hold completed" — the island
                    // showed "SOS ACTIVE" the instant the dial was held,
                    // before anyone had actually sent anything, which read
                    // as "already sent." It only flips to a real sent
                    // state now, from the real compose result.
                    LiveActivityManager.shared.updateSOSMessageSent(result == .sent)
                    if result == .sent {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
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
            Text(canMessage ? "SOS · MESSAGES YOUR CONTACTS" : "SOS · NO SIGNAL TO SEND")
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
            if !isTriggered {
                Text("Emergency\nSOS")
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
                    .scaleEffect(isTriggered ? 1.05 : (1 - holdProgress * 0.04))

                VStack(spacing: 6) {
                    if messageResult == .sent {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 22))
                    } else if isTriggered {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 20))
                    }
                    Text(dialTitle)
                        .font(NTFont.heading(isTriggered ? 20 : 30, .extraBold))
                        .tracking(0.4)
                        .multilineTextAlignment(.center)
                    Text(dialSubtitle)
                        .font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.75))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
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
            // Real, not boilerplate — this is the one place someone about
            // to rely on this screen actually reads it.
            Text("Not a satellite beacon. Nothing here is monitored — only your contacts will see this if they open the message. Call local emergency services directly when you have signal.")
                .font(NTFont.body(11, .medium))
                .foregroundStyle(NTColor.milk(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
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

            if isTriggered && canMessage && !textableContacts.isEmpty {
                Button(action: { showMessageCompose = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "message.fill")
                        Text(messageResult == .sent ? "Send again" : "Message emergency contacts").font(NTFont.body(13, .semibold))
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
        guard holdTimer == nil, !isTriggered else { return }
        holdTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { _ in
            holdProgress = min(1, holdProgress + 0.03 / 2.4)
            if holdProgress >= 1 {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                withAnimation(NTMotion.spring) { isTriggered = true }
                RouteRepository.shared.logEvent("sos_triggered")
                onTriggered()
                holdTimer?.invalidate()
                holdTimer = nil
                // Opens the real Messages compose sheet right away rather
                // than making it a second, easy-to-miss tap — but this is
                // still only an offer to send, not a send. `messageResult`
                // (and therefore `dialTitle`/`dialSubtitle`) stays honest
                // either way: nil until the sheet actually reports an
                // outcome, so the dial never claims more than really
                // happened.
                if canMessage && !textableContacts.isEmpty {
                    showMessageCompose = true
                }
            }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        if !isTriggered {
            withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
        }
    }
}
