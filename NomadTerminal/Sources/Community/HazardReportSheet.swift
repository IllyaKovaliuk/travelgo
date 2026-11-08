import SwiftUI
import CoreLocation
import AVFoundation

/// Bottom sheet for filing a hazard: category grid, optional note, optional
/// camera photo. Location is the user's current position.
struct HazardReportSheet: View {
    let coordinate: CLLocationCoordinate2D?
    let store: HazardStore
    let onDone: () -> Void

    @State private var type: HazardType = .treeFall
    @State private var note = ""
    @State private var photo: UIImage?
    @State private var showCamera = false
    @State private var cameraDenied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Report a hazard").font(NTFont.heading(22, .extraBold))
            Text("Help the next person through. +50 NomadPoints per report, up to 5 a day.")
                .font(NTFont.body(12.5, .light)).foregroundStyle(NTColor.milk(0.6))
            Text("\(store.reportsLeftToday) of \(HazardStore.dailyLimit) reports left today")
                .font(NTFont.mono(10.5, .medium)).foregroundStyle(store.reportsLeftToday == 0 ? Color(hex: 0xE58272) : NTColor.sage)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(HazardType.allCases) { option in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        type = option
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: option.icon).font(.system(size: 22))
                            Text(option.title).font(NTFont.body(13, .semibold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 78)
                        .foregroundStyle(type == option ? NTColor.pine : NTColor.milk)
                        .background(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                            .fill(type == option ? NTColor.milk : NTColor.milk(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                            .stroke(NTColor.milk(type == option ? 0 : 0.14), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            TextField("", text: $note, prompt: Text("Short note (optional)").foregroundStyle(NTColor.milk(0.35)), axis: .vertical)
                .lineLimit(1...3)
                .font(NTFont.body(14))
                .onChange(of: note) { _, new in if new.count > 280 { note = String(new.prefix(280)) } }
                .padding(14)
                .background(NTColor.milk(0.08), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))

            HStack(spacing: 12) {
                Button { openCamera() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: photo == nil ? "camera.fill" : "checkmark.circle.fill")
                        Text(photo == nil ? "Add photo" : "Photo added")
                    }
                    .font(NTFont.body(13.5, .semibold))
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(Capsule().fill(NTColor.milk(0.1)))
                    .overlay(Capsule().stroke(NTColor.milk(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                if let photo {
                    Image(uiImage: photo).resizable().scaledToFill()
                        .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Spacer()
            }

            if let error = store.errorMessage {
                Text(error).font(NTFont.body(12.5, .medium)).foregroundStyle(Color(hex: 0xE58272))
            }

            Button {
                guard let coordinate else { return }
                Task {
                    if await store.submit(type: type, at: coordinate, description: note, photo: photo) { onDone() }
                }
            } label: {
                HStack {
                    if store.isSubmitting { ProgressView().tint(NTColor.pine) }
                    Text(coordinate == nil ? "Waiting for GPS…" : "Submit report").font(NTFont.body(15, .semibold))
                }
                .foregroundStyle(NTColor.pine)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Capsule().fill(coordinate == nil ? NTColor.milk(0.4) : NTColor.milk))
            }
            .buttonStyle(.plain)
            .disabled(coordinate == nil || store.isSubmitting || store.reportsLeftToday == 0)
        }
        .padding(22)
        .foregroundStyle(NTColor.milk)
        .background(NTColor.pine.ignoresSafeArea())
        .onAppear { store.errorMessage = nil }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { photo = $0 }.ignoresSafeArea()
        }
        // The photo is optional — a denied camera must never trap or crash
        // the report flow; explain and offer Settings, then carry on.
        .alert("Camera access is off", isPresented: $cameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("You can still send this report without a photo, or allow camera access in Settings to add one.")
        }
    }

    private func openCamera() {
        // No camera hardware (simulator) -> CameraPicker falls back to the
        // photo library, which needs no permission.
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { showCamera = true; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .denied, .restricted:
            cameraDenied = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { showCamera = true } else { cameraDenied = true }
                }
            }
        default:
            showCamera = true
        }
    }
}
