import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

/// 14b · Import — was one of the three "how did you get the line" options
/// in `LogRouteStartView` that did nothing at all before this. Real GPX/KML
/// parsing (`RouteFileParser`), same distance/ascent math `RouteTracker`
/// uses for a live recording (`TrackMath`, a batch version of the same
/// formulas), then feeds the exact same `RecordResult` → `NewRouteDraft`
/// pipeline `RecordTrackView` and `DrawRouteView` both feed — nothing
/// downstream (`RouteUploadDetailsView`, publish) needed to change.
struct ImportRouteView: View {
    var onFinish: (RecordResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showPicker = false
    @State private var isParsing = false
    @State private var errorMessage: String?
    @State private var parsed: ParsedFile?
    @State private var transport: Transport = .foot

    private struct ParsedFile {
        let fileName: String
        let points: [ParsedTrackPoint]
        let distanceKM: Double
        let ascentM: Double
        let highPointM: Double
    }

    /// Dynamically constructed rather than declared in Info.plist — GPX/KML
    /// aren't system UTTypes, and this is enough for the picker to filter
    /// and show the right icon without an Info.plist UTI export/import
    /// declaration for a two-format, read-only picker.
    private var allowedTypes: [UTType] {
        [UTType(filenameExtension: "gpx"), UTType(filenameExtension: "kml"), .xml].compactMap { $0 }
    }

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                header
                if let parsed {
                    previewContent(parsed)
                } else {
                    intro
                }
                Spacer()
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: allowedTypes, onCompletion: handlePicked)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(NTColor.milk(0.08)))
                    .overlay(Circle().stroke(NTColor.milk(0.18), lineWidth: 1))
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Import a file").font(NTFont.body(15, .semibold))
            Spacer()
            Color.clear.frame(width: 42, height: 42)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 18) {
            if isParsing {
                ProgressView().tint(NTColor.milk)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 70)
            } else {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 34))
                    .foregroundStyle(NTColor.water)
                    .padding(.top, 50)

                Text("Import a GPX\nor KML file")
                    .font(NTFont.heading(30, .extraBold))
                    .foregroundStyle(NTColor.milk)

                Text("Export a track from Garmin Connect, Strava, AllTrails, Komoot or any app that saves a GPX or KML file.")
                    .font(NTFont.body(14, .light))
                    .foregroundStyle(NTColor.milk(0.62))

                if let errorMessage {
                    Text(errorMessage)
                        .font(NTFont.body(12.5, .medium))
                        .foregroundStyle(NTColor.hardBright)
                }

                Button {
                    showPicker = true
                } label: {
                    Text("Choose file")
                        .font(NTFont.body(15, .semibold))
                        .foregroundStyle(Color(hex: 0x231007))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(NTColor.water, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
    }

    private func previewContent(_ parsed: ParsedFile) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 24)).foregroundStyle(NTColor.sage)
                Text(parsed.fileName)
                    .font(NTFont.heading(20, .bold))
                    .foregroundStyle(NTColor.milk)
                    .lineLimit(1)
                Text("\(parsed.points.count) points read")
                    .font(NTFont.mono(11, .medium)).tracking(0.4)
                    .foregroundStyle(NTColor.milk(0.5))
            }
            .padding(.top, 30)

            HStack(spacing: 0) {
                stat(String(format: "%.2f", parsed.distanceKM), "KM", "DISTANCE")
                stat(String(format: "%.0f", parsed.ascentM), "M", "ASCENT")
                stat(String(format: "%.0f", parsed.highPointM), "M", "HIGH POINT")
            }
            .padding(20)
            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))

            VStack(alignment: .leading, spacing: 10) {
                Text("TRANSPORT").font(NTFont.mono(9.5, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
                TransportPicker(selection: $transport)
            }

            Button {
                finish(parsed)
            } label: {
                Text("Use this track")
                    .font(NTFont.body(15, .semibold))
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(NTColor.milk, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                self.parsed = nil
            } label: {
                Text("Choose a different file")
                    .font(NTFont.body(13.5, .medium))
                    .foregroundStyle(NTColor.milk(0.6))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
    }

    private func stat(_ value: String, _ unit: String, _ label: String) -> some View {
        VStack(spacing: 6) {
            (Text(value).font(NTFont.mono(16, .semibold)) + Text(" " + unit).font(NTFont.mono(9, .medium)).foregroundStyle(NTColor.milk(0.55)))
            Text(label).font(NTFont.mono(8.5, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private func handlePicked(_ result: Result<URL, Error>) {
        errorMessage = nil
        switch result {
        case .failure:
            errorMessage = "Couldn't open that file — try again."
        case .success(let url):
            isParsing = true
            Task {
                defer { isParsing = false }
                let needsSecurityScope = url.startAccessingSecurityScopedResource()
                defer { if needsSecurityScope { url.stopAccessingSecurityScopedResource() } }
                do {
                    let points = try RouteFileParser.parse(fileURL: url)
                    let coordinates = points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                    let elevations = points.compactMap(\.elevation)
                    parsed = ParsedFile(
                        fileName: url.lastPathComponent,
                        points: points,
                        distanceKM: TrackMath.distanceKM(coordinates),
                        ascentM: elevations.isEmpty ? 0 : TrackMath.ascentM(elevations),
                        highPointM: elevations.isEmpty ? 0 : TrackMath.highPointM(elevations)
                    )
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't read that file."
                }
            }
        }
    }

    private func finish(_ parsed: ParsedFile) {
        let trackPoints = TrackMath.downsample(parsed.points.map { TrackPoint(lat: $0.lat, lng: $0.lng) })
        onFinish(RecordResult(
            distanceKM: parsed.distanceKM, ascentM: parsed.ascentM, highPointM: parsed.highPointM,
            points: trackPoints, pois: [], transport: transport
        ))
    }
}
