import SwiftUI
import PhotosUI
import UIKit

/// 15 · Log a route — details. Real text fields feeding a draft that gets
/// published for real on the last step.
struct RouteUploadDetailsView: View {
    @Binding var draft: NewRouteDraft
    var onContinue: () -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var isUploadingCover = false
    @State private var coverUploadError: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    stepHeader(title: "Route details", step: 1)

                    coverSlot

                    field(label: "TITLE") {
                        TextField("", text: $draft.title, prompt: Text("Zagar Pass at first light").foregroundStyle(NTColor.milk(0.3)))
                            .font(NTFont.heading(15, .bold))
                    }
                    .padding(.top, 18)

                    field(label: "REGION") {
                        TextField("", text: $draft.place, prompt: Text("Svaneti, Georgia").foregroundStyle(NTColor.milk(0.3)))
                            .font(NTFont.body(14.5, .medium))
                    }
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TRANSPORT").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                        HStack(spacing: 10) {
                            ForEach(Transport.allCases, id: \.self) { t in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    draft.transport = t
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: t.icon).font(.system(size: 18))
                                        Text(t.rawValue).font(NTFont.mono(8.5, .semibold))
                                    }
                                    .foregroundStyle(draft.transport == t ? Color(hex: 0x231007) : NTColor.milk(0.75))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(draft.transport == t ? t.color : NTColor.milk(0.08)))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: draft.transport == t ? 0 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("DIFFICULTY").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                        HStack(spacing: 8) {
                            ForEach([Route.Difficulty.easy, .moderate, .hard], id: \.self) { d in
                                Button {
                                    draft.difficulty = d
                                } label: {
                                    Text(d.rawValue)
                                        .font(NTFont.mono(12.5, .semibold)).tracking(0.4)
                                        .foregroundStyle(draft.difficulty == d ? NTColor.milk : NTColor.milk(0.6))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Capsule().fill(draft.difficulty == d ? d.color : .clear))
                                        .overlay(Capsule().stroke(NTColor.milk(0.2), lineWidth: draft.difficulty == d ? 0 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 18)

                    field(label: "DISTANCE (KM)") {
                        TextField("", text: $draft.distanceKM, prompt: Text("62.4").foregroundStyle(NTColor.milk(0.3)))
                            .keyboardType(.decimalPad)
                            .font(NTFont.mono(14, .semibold))
                    }
                    .padding(.top, 14)

                    HStack(spacing: 12) {
                        field(label: "SEASON") {
                            TextField("", text: $draft.season, prompt: Text("JUN – OCT").foregroundStyle(NTColor.milk(0.3)))
                                .font(NTFont.body(13.5, .medium))
                        }
                        field(label: "DURATION") {
                            TextField("", text: $draft.duration, prompt: Text("2 DAYS").foregroundStyle(NTColor.milk(0.3)))
                                .font(NTFont.body(13.5, .medium))
                        }
                    }
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("A NOTE FOR OTHERS (OPTIONAL)").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                        TextField("", text: $draft.quote, prompt: Text("Leave before four — the pass holds cloud until sunrise.").foregroundStyle(NTColor.milk(0.3)), axis: .vertical)
                            .font(NTFont.body(13.5, .regular))
                            .foregroundStyle(NTColor.milk)
                            .lineLimit(2...4)
                            .padding(14)
                            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
                    }
                    .padding(.top, 14)

                    segmentsSection.padding(.top, 22)
                    requirementsSection.padding(.top, 22)
                    if !draft.pois.isEmpty {
                        poisSection.padding(.top, 22)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            NTPrimaryButton(title: "Continue", icon: "arrow.right", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(NTColor.pine)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var coverSlot: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(NTColor.milk(0.05))
                    .frame(height: 150)

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        .foregroundStyle(NTColor.milk(0.28))
                        .frame(height: 150)
                }

                if isUploadingCover {
                    ZStack {
                        RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.black.opacity(0.4))
                        ProgressView().tint(NTColor.milk)
                    }
                    .frame(height: 150)
                } else if previewImage == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 24, weight: .light))
                        Text("Add cover photo").font(NTFont.body(12.5, .semibold))
                    }
                    .foregroundStyle(NTColor.milk(0.6))
                } else if draft.coverImageUrl != nil {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NTColor.sage)
                                .padding(10)
                        }
                        Spacer()
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.top, 20)
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await uploadCover(newItem) }
        }
        .overlay(alignment: .bottom) {
            if let coverUploadError {
                Text(coverUploadError)
                    .font(NTFont.body(11, .medium))
                    .foregroundStyle(Color(hex: 0xE58272))
                    .padding(.bottom, -18)
            }
        }
    }

    private func uploadCover(_ item: PhotosPickerItem) async {
        coverUploadError = nil
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            coverUploadError = "Couldn't load that photo — try another."
            return
        }
        withAnimation { previewImage = image }
        // Downscale before upload — a full-res phone photo is overkill for
        // a card thumbnail and needlessly slow to upload over cellular.
        let resized = image.resized(maxDimension: 1600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.82) else { return }

        isUploadingCover = true
        do {
            draft.coverImageUrl = try await RouteRepository.shared.uploadCoverImage(jpeg)
        } catch {
            coverUploadError = "Upload failed — check your connection and try again."
        }
        isUploadingCover = false
    }

    private func stepHeader(title: String, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(NTFont.body(15, .semibold))
                Spacer()
                Text("\(step) OF 3").font(NTFont.mono(10, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.5))
            }
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in
                    Capsule().fill(i <= step ? NTColor.milk : NTColor.milk(0.2)).frame(height: 3)
                }
            }
        }
    }

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SEGMENTS (OPTIONAL)").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                Spacer()
                addButton { draft.segments.append(DraftSegment()) }
            }
            ForEach($draft.segments) { $segment in
                HStack(spacing: 10) {
                    Menu {
                        ForEach(Transport.allCases, id: \.self) { t in
                            Button { segment.transport = t } label: { Label(t.rawValue, systemImage: t.icon) }
                        }
                    } label: {
                        Image(systemName: segment.transport.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(NTColor.milk)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(segment.transport.color.opacity(0.35)))
                    }
                    TextField("", text: $segment.name, prompt: Text("Segment name").foregroundStyle(NTColor.milk(0.3)))
                        .font(NTFont.body(13.5, .medium))
                        .foregroundStyle(NTColor.milk)
                    TextField("", text: $segment.distanceKM, prompt: Text("KM").foregroundStyle(NTColor.milk(0.3)))
                        .keyboardType(.decimalPad)
                        .font(NTFont.mono(12.5, .semibold))
                        .foregroundStyle(NTColor.milk)
                        .frame(width: 50)
                    removeButton { draft.segments.removeAll { $0.id == segment.id } }
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("REQUIREMENTS & GEAR (OPTIONAL)").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                Spacer()
                addButton { draft.requirements.append(DraftRequirement()) }
            }
            ForEach($draft.requirements) { $req in
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Menu {
                            ForEach(RequirementCategory.allCases, id: \.self) { c in
                                Button { req.category = c } label: { Label(c.rawValue, systemImage: c.icon) }
                            }
                        } label: {
                            Image(systemName: req.category.icon)
                                .font(.system(size: 15))
                                .foregroundStyle(NTColor.milk)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(req.category.tint.opacity(0.35)))
                        }
                        TextField("", text: $req.title, prompt: Text("Requirement").foregroundStyle(NTColor.milk(0.3)))
                            .font(NTFont.body(13.5, .medium))
                            .foregroundStyle(NTColor.milk)
                        removeButton { draft.requirements.removeAll { $0.id == req.id } }
                    }
                    TextField("", text: $req.subtitle, prompt: Text("Detail (optional)").foregroundStyle(NTColor.milk(0.3)))
                        .font(NTFont.mono(11, .medium))
                        .foregroundStyle(NTColor.milk(0.8))
                }
                .padding(14)
                .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    /// Read-only list of the pins dropped mid-recording — position came
    /// from real GPS at drop time, so there's nothing to edit here besides
    /// removing one.
    private var poisSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PINS DROPPED (\(draft.pois.count))").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
            ForEach(draft.pois) { poi in
                HStack(spacing: 10) {
                    ZStack {
                        Circle().fill(poi.category.tint)
                        Image(systemName: poi.category.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(poi.title).font(NTFont.body(13.5, .medium)).foregroundStyle(NTColor.milk)
                        if !poi.note.isEmpty {
                            Text(poi.note).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.5)).lineLimit(1)
                        }
                    }
                    Spacer()
                    removeButton { draft.pois.removeAll { $0.id == poi.id } }
                }
                .padding(12)
                .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func addButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(NTColor.pine)
                .frame(width: 26, height: 26)
                .background(Circle().fill(NTColor.milk))
        }
        .buttonStyle(.plain)
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(NTColor.milk(0.6))
                .frame(width: 26, height: 26)
                .background(Circle().fill(NTColor.milk(0.1)))
        }
        .buttonStyle(.plain)
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
            content()
                .foregroundStyle(NTColor.milk)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
        }
    }
}

private extension UIImage {
    /// Scales down to fit within `maxDimension` on the long edge, preserving
    /// aspect ratio. A no-op if the image is already smaller.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDimension else { return self }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
