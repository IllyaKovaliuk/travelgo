import SwiftUI
import MapboxMaps
import CoreLocation
import AVFoundation

/// Hazards (pulsating red) and verified partners (gold badge) as map
/// annotations. Shared by every map that shows the community layer.
struct CommunityMapContent: MapContent {
    let hazards: [HazardReport]
    let partners: [Partner]
    let onHazard: (HazardReport) -> Void
    let onPartner: (Partner) -> Void

    var body: some MapContent {
        ForEvery(partners) { partner in
            MapViewAnnotation(coordinate: partner.coordinate) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onPartner(partner)
                } label: { PartnerMapMarker(partner: partner) }
                .buttonStyle(.plain)
            }
        }
        ForEvery(hazards) { hazard in
            MapViewAnnotation(coordinate: hazard.coordinate) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onHazard(hazard)
                } label: { HazardMapMarker(type: hazard.hazardType) }
                .buttonStyle(.plain)
            }
        }
    }
}

struct HazardMapMarker: View {
    let type: HazardType
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(NTColor.hard.opacity(0.35))
                .frame(width: 46, height: 46)
                .scaleEffect(pulse ? 1.5 : 0.8)
                .opacity(pulse ? 0 : 0.8)
            Circle().fill(NTColor.hard)
                .frame(width: 32, height: 32)
                .overlay(Circle().stroke(.white, lineWidth: 2))
            Image(systemName: type.icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 52, height: 52)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

struct PartnerMapMarker: View {
    let partner: Partner

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle().fill(NTColor.gold)
                .frame(width: 36, height: 36)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .overlay(Image(systemName: partner.category.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(NTColor.ink))
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14))
                .foregroundStyle(.white, NTColor.sage)
                .offset(x: 4, y: 4)
        }
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

/// Bottom card for a tapped hazard: details, photo, and confirm/dismiss.
struct HazardDetailCard: View {
    let hazard: HazardReport
    var showsVoting = true
    let isVoting: Bool
    let onConfirm: () -> Void
    let onDismiss: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: hazard.hazardType.icon).foregroundStyle(NTColor.hard)
                Text(hazard.hazardType.title).font(NTFont.body(15, .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
                        .background(Circle().fill(NTColor.milk(0.1)))
                }.buttonStyle(.plain)
            }
            if let urlString = hazard.imageUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { NTColor.milk(0.06) }
                    .frame(height: 120).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            }
            if let d = hazard.description, !d.isEmpty {
                Text(d).font(NTFont.body(13, .light)).foregroundStyle(NTColor.milk(0.75))
            }
            Text("\(hazard.confirmations) confirmed · \(hazard.dismissals) say it's gone · \(hazard.createdAt.formatted(.relative(presentation: .named)))")
                .font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.5))
            if showsVoting {
            HStack(spacing: 10) {
                voteButton("Still there", icon: "checkmark", fill: NTColor.milk, text: NTColor.pine, action: onConfirm)
                voteButton("It's gone", icon: "xmark", fill: NTColor.milk(0.12), text: NTColor.milk, action: onDismiss)
            }
            Text("Votes only count within 300 m of the hazard.")
                .font(NTFont.body(10.5, .light)).foregroundStyle(NTColor.milk(0.4))
            }
        }
        .padding(16)
        .background(NTColor.pineDeep, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }

    private func voteButton(_ title: LocalizedStringKey, icon: String, fill: Color, text: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isVoting { ProgressView().tint(text) } else { Image(systemName: icon) }
                Text(title).font(NTFont.body(13.5, .semibold))
            }
            .foregroundStyle(text)
            .frame(maxWidth: .infinity).frame(height: 40)
            .background(Capsule().fill(fill))
        }
        .buttonStyle(.plain).disabled(isVoting)
    }
}

struct PartnerDetailCard: View {
    let partner: Partner
    let onOpenStore: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PartnerMapMarker(partner: partner)
            VStack(alignment: .leading, spacing: 3) {
                Text(partner.name).font(NTFont.body(15, .semibold))
                Text(partner.category.title).font(NTFont.body(12, .light)).foregroundStyle(NTColor.milk(0.6))
            }
            Spacer()
            Button(action: onOpenStore) {
                Text("Offers").font(NTFont.body(13, .semibold)).foregroundStyle(NTColor.pine)
                    .padding(.horizontal, 16).frame(height: 36).background(Capsule().fill(NTColor.milk))
            }.buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
                    .background(Circle().fill(NTColor.milk(0.1)))
            }.buttonStyle(.plain)
        }
        .padding(14)
        .background(NTColor.pineDeep, in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }
}

/// Floating hazard button — sits above the geolocation controls.
struct HazardFAB: View {
    let action: () -> Void
    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(NTColor.hard))
                .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Report a hazard")
    }
}

/// "+50 NomadPoints" celebration shown after a successful report.
struct PointsBurstOverlay: View {
    let points: Int
    @State private var shown = false

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.fill").font(.system(size: 30)).foregroundStyle(NTColor.gold)
            Text("+\(points)").font(NTFont.heading(44, .extraBold))
            Text("NOMADPOINTS").font(NTFont.mono(11, .medium)).tracking(1.4).foregroundStyle(NTColor.milk(0.7))
        }
        .foregroundStyle(NTColor.milk)
        .padding(.horizontal, 36).padding(.vertical, 24)
        .background(NTColor.pineDeep.opacity(0.92), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.gold.opacity(0.6), lineWidth: 1.5))
        .scaleEffect(shown ? 1 : 0.5)
        .offset(y: shown ? 0 : 30)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { shown = true } }
    }
}

/// System camera (falls back to the photo library where no camera exists,
/// e.g. the simulator).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// "Hazard ahead" banner shown when the user nears a reported hazard.
struct HazardProximityBanner: View {
    let alert: HazardStore.ProximityAlert
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alert.hazard.hazardType.icon)
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 36, height: 36).background(Circle().fill(NTColor.hard))
            VStack(alignment: .leading, spacing: 2) {
                Text("Hazard ahead").font(NTFont.mono(10, .semibold)).tracking(0.8).foregroundStyle(NTColor.milk(0.7))
                HStack(spacing: 6) {
                    Text(alert.hazard.hazardType.title).font(NTFont.body(14.5, .semibold))
                    Text("· \(alert.distanceM) m").font(NTFont.mono(12, .medium)).foregroundStyle(NTColor.milk(0.7))
                }
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold)).frame(width: 28, height: 28)
                    .background(Circle().fill(NTColor.milk(0.12)))
            }.buttonStyle(.plain)
        }
        .padding(12)
        .background(NTColor.hard.opacity(0.9), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(.white.opacity(0.35), lineWidth: 1))
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
