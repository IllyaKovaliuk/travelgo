import SwiftUI

/// 14 · Recording — live. Real CoreLocation recording via `RouteTracker`:
/// distance/ascent/the stored polyline all come from actual GPS fixes, not
/// a simulated pace. Elapsed time is real wall-clock time.
struct RecordTrackView: View {
    /// distanceKM, ascentM, recorded points.
    var onFinish: (Double, Double, [TrackPoint]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tracker = RouteTracker()
    @State private var elapsed: TimeInterval = 0
    @State private var isPaused = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            terrain

            VStack {
                header
                Spacer()
                if tracker.authorizationDenied {
                    locationDeniedCard
                } else {
                    statsCard
                }
                Spacer().frame(height: 18)
                controls
            }
        }
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { tracker.start() }
        .onDisappear { tracker.stop() }
        .onReceive(timer) { _ in
            guard !isPaused else { return }
            elapsed += 1
        }
    }

    private var locationDeniedCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash.fill").font(.system(size: 26)).foregroundStyle(Color(hex: 0xE58272))
            Text("Location access needed to record a track").font(NTFont.body(14.5, .semibold))
            Text("Enable it in Settings to log real distance, ascent and your path.")
                .font(NTFont.body(12.5, .light))
                .foregroundStyle(NTColor.milk(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .padding(.horizontal, 22)
    }

    private var terrain: some View {
        ZStack {
            NTColor.pineDeep.ignoresSafeArea()
            OrganicBlob((0.15, 0.55, 0.3, 0.1), (0.1, 0.2, 0.7, 0.5))
                .fill(NTColor.pineShadow)
                .frame(width: 500, height: 400)
                .position(x: 120, y: 200)
                .ignoresSafeArea()
            OrganicBlob((0.4, 0.2, 0.35, 0.5), (0.4, 0.1, 0.55, 0.35))
                .fill(NTColor.pineRaised.opacity(0.6))
                .frame(width: 460, height: 360)
                .position(x: 320, y: 480)
                .ignoresSafeArea()
                .ambientDrift(dx: 6, dy: 8, duration: 9)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xE58272)).frame(width: 7, height: 7)
                    .opacity(isPaused ? 1 : 0.4)
                    .overlay(
                        Circle().fill(Color(hex: 0xE58272))
                            .scaleEffect(isPaused ? 1 : 1.8)
                            .opacity(isPaused ? 0 : 0.6)
                            .animation(.easeOut(duration: 1.1).repeatForever(autoreverses: false), value: isPaused)
                    )
                Text(isPaused ? "PAUSED" : "RECORDING")
                    .font(NTFont.mono(11, .semibold)).tracking(0.8)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(Color(hex: 0xB33A2B).opacity(0.25)))
            .overlay(Capsule().stroke(Color(hex: 0xB33A2B).opacity(0.5), lineWidth: 1))

            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private var statsCard: some View {
        VStack(spacing: 16) {
            Text(formattedTime)
                .font(NTFont.mono(46, .semibold))
                .contentTransition(.numericText())

            HStack(spacing: 0) {
                stat(String(format: "%.2f", tracker.distanceKM), "KM", "DISTANCE")
                stat(String(format: "%.0f", tracker.ascentM), "M", "ASCENT")
                stat(String(format: "%.1f", tracker.distanceKM > 0 ? tracker.distanceKM / (elapsed / 3600 + 0.001) : 0), "KM/H", "AVG SPEED")
            }
        }
        .padding(24)
        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .padding(.horizontal, 22)
    }

    private func stat(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            (Text(value).font(NTFont.mono(18, .semibold)) + Text(" " + unit).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55)))
            Text(label).font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation { isPaused.toggle() }
                if isPaused { tracker.pause() } else { tracker.resume() }
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 20))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1.4))
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                tracker.stop()
                onFinish(tracker.distanceKM, tracker.ascentM, tracker.storedPoints)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Finish").font(NTFont.body(15, .semibold))
                }
                .foregroundStyle(NTColor.pine)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(NTColor.milk, in: Capsule())
            }
            .buttonStyle(.plain)
            .ntPressable()

            Button {} label: {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 19))
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.25), lineWidth: 1.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }

    private var formattedTime: String {
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
