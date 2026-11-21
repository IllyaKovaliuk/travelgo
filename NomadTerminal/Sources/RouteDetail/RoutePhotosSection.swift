import SwiftUI
import PhotosUI

/// Part 2 — the lightweight photo social layer on a route. Same data
/// pattern as `CommentsView` (user + route + timestamp + content, fetched
/// separately from `Route` itself, not embedded in `RouteDTO`) and the
/// same moderation path (`RouteRepository.report(.photo, ...)`, feeding
/// the same `content_reports` auto-hide trigger comments/routes already
/// use). Grid thumbnails on the existing dark surface tokens; tapping one
/// opens `PhotoViewerView`, a simple swipeable full-screen viewer — no new
/// colors or typography introduced anywhere in this file.
struct RoutePhotosSection: View {
    let routeId: String
    let currentUserId: String?
    /// Unlike comments, adding a photo is NOT open to anyone signed in —
    /// only the route's own author can (enforced for real by
    /// `route_photos`' INSERT policy; this just keeps the "+" button from
    /// showing to someone whose tap would fail anyway). Anyone can still
    /// view, and the uploader — always the owner now — can delete their
    /// own.
    let isOwner: Bool

    @State private var photos: [RouteRepository.RoutePhoto] = []
    @State private var isLoading = true
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var viewerIndex: Int?
    @State private var reportingPhotoID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                Text("Photos").font(NTFont.heading(18, .bold)).foregroundStyle(NTColor.milk)
                if !photos.isEmpty {
                    Text("\(photos.count)").font(NTFont.mono(10, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5))
                }
                Spacer()
                if isOwner {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        if isUploading {
                            ProgressView().tint(NTColor.milk)
                        } else {
                            Image(systemName: "plus.circle.fill").font(.system(size: 20)).foregroundStyle(NTColor.milk(0.7))
                        }
                    }
                    .disabled(isUploading)
                }
            }

            if isLoading {
                ProgressView().tint(NTColor.milk).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if photos.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            thumbnail(photo).onTapGesture { viewerIndex = index }
                        }
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await upload(newItem) }
        }
        .ntFullScreenCover(item: Binding(
            get: { viewerIndex.map { PhotoViewerIndex(index: $0) } },
            set: { viewerIndex = $0?.index }
        ), readable: false) { wrapped in
            PhotoViewerView(
                photos: photos, startIndex: wrapped.index, currentUserId: currentUserId,
                onDelete: { photo in
                    photos.removeAll { $0.id == photo.id }
                    Task { try? await RouteRepository.shared.deletePhoto(id: photo.id) }
                },
                onReport: { photo in reportingPhotoID = photo.id },
                onClose: { viewerIndex = nil }
            )
        }
        .confirmationDialog("Why are you reporting this photo?", isPresented: Binding(
            get: { reportingPhotoID != nil },
            set: { if !$0 { reportingPhotoID = nil } }
        ), titleVisibility: .visible) {
            ForEach(["Spam", "Harassment", "Inappropriate content", "Other"], id: \.self) { reason in
                Button(reason) { report(reason: reason) }
            }
            Button("Cancel", role: .cancel) { reportingPhotoID = nil }
        }
    }

    private struct PhotoViewerIndex: Identifiable { let index: Int; var id: Int { index } }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle").font(.system(size: 24)).foregroundStyle(NTColor.milk(0.3))
            Text(isOwner ? "No photos yet — add one from the trip" : "No photos yet")
                .font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
    }

    private func thumbnail(_ photo: RouteRepository.RoutePhoto) -> some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: photo.imageUrl)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(NTColor.milk(0.08))
                }
            }
            .frame(width: 118, height: 118)
            .clipShape(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))

            // Small avatar/username attribution, per spec — same
            // gradient-initials treatment `CommentsView`/`AuthorProfileView`
            // already use rather than a second avatar-loading path.
            HStack(spacing: 4) {
                ZStack {
                    LinearGradient(colors: [NTColor.water, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(photo.uploaderInitials).font(NTFont.mono(7, .semibold)).foregroundStyle(.white)
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())
            }
            .padding(6)
        }
        .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
    }

    private func load() async {
        photos = (try? await RouteRepository.shared.fetchPhotos(routeId: routeId)) ?? []
        withAnimation { isLoading = false }
    }

    private func upload(_ item: PhotosPickerItem) async {
        isUploading = true
        defer { isUploading = false; pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        do {
            let url = try await RouteRepository.shared.uploadRoutePhotoFile(data, routeId: routeId)
            // No lat/lng — this is the after-the-fact upload path (Part 2b),
            // not the mid-recording geotagged one (Part 2a, RecordTrackView).
            try await RouteRepository.shared.addPhoto(routeId: routeId, imageUrl: url, lat: nil, lng: nil, caption: nil)
            RouteRepository.shared.logEvent("route_photo_added")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func report(reason: String) {
        guard let id = reportingPhotoID else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        reportingPhotoID = nil
        Task { try? await RouteRepository.shared.report(.photo, id: id, reason: reason) }
    }
}

/// Simple swipeable full-screen viewer — `TabView` paging, not a custom
/// gesture-driven pager, since that's all "swipeable between a route's
/// photos" needs.
struct PhotoViewerView: View {
    let photos: [RouteRepository.RoutePhoto]
    let startIndex: Int
    let currentUserId: String?
    var onDelete: (RouteRepository.RoutePhoto) -> Void
    var onReport: (RouteRepository.RoutePhoto) -> Void
    var onClose: () -> Void

    @State private var index: Int

    init(photos: [RouteRepository.RoutePhoto], startIndex: Int, currentUserId: String?, onDelete: @escaping (RouteRepository.RoutePhoto) -> Void, onReport: @escaping (RouteRepository.RoutePhoto) -> Void, onClose: @escaping () -> Void) {
        self.photos = photos
        self.startIndex = startIndex
        self.currentUserId = currentUserId
        self.onDelete = onDelete
        self.onReport = onReport
        self.onClose = onClose
        _index = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { i, photo in
                    AsyncImage(url: URL(string: photo.imageUrl)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            VStack {
                header
                Spacer()
                if photos.indices.contains(index) {
                    footer(photos[index])
                }
            }
        }
        .statusBarHidden()
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
            .buttonStyle(.plain)
            Spacer()
            if photos.count > 1 {
                Text("\(index + 1) / \(photos.count)")
                    .font(NTFont.mono(11, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.4)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
    }

    private func footer(_ photo: RouteRepository.RoutePhoto) -> some View {
        HStack {
            HStack(spacing: 8) {
                ZStack {
                    LinearGradient(colors: [NTColor.water, NTColor.pineRaised], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(photo.uploaderInitials).font(NTFont.mono(9, .semibold)).foregroundStyle(.white)
                }
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(photo.uploaderName).font(NTFont.body(12.5, .semibold)).foregroundStyle(.white)
                    Text(photo.createdAgo).font(NTFont.mono(9.5, .medium)).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer()
            Menu {
                if photo.uploaderId == currentUserId {
                    Button(role: .destructive) { onDelete(photo); onClose() } label: {
                        Label("Delete photo", systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) { onReport(photo) } label: {
                        Label("Report photo", systemImage: "flag")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.black.opacity(0.4)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
    }
}
