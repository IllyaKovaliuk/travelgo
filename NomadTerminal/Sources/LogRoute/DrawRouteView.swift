import SwiftUI
import MapboxMaps
import CoreLocation

/// 14c · Draw — the third "how did you get the line" option that did
/// nothing before this. Tap the satellite map to lay down waypoints;
/// distance is real (`TrackMath.distanceKM`, same ground-distance math as
/// a live recording), ascent/high point are honestly 0 — tapping a flat
/// map screen has no elevation data, and this app has never fabricated a
/// stat it can't back with something real. Feeds the same `RecordResult`
/// pipeline `RecordTrackView`/`ImportRouteView` do.
struct DrawRouteView: View {
    var onFinish: (RecordResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var points: [CLLocationCoordinate2D] = []
    @State private var transport: Transport = .foot
    @State private var viewport: Viewport = .camera(
        center: CLLocationCoordinate2D(latitude: 20, longitude: 15), zoom: 1.6, bearing: 0, pitch: 0
    )

    private var distanceKM: Double { TrackMath.distanceKM(points) }

    var body: some View {
        ZStack(alignment: .top) {
            Map(viewport: $viewport) {
                if points.count > 1 {
                    PolylineAnnotation(lineCoordinates: points)
                        .lineColor(UIColor(NTColor.accent))
                        .lineWidth(4)
                        .lineJoin(.round)
                        .lineOpacity(0.95)
                }
                ForEvery(Array(points.enumerated()), id: \.offset) { index, coordinate in
                    MapViewAnnotation(coordinate: coordinate) {
                        pointMarker(isLast: index == points.count - 1)
                    }
                }
            }
            .mapStyle(.standardSatellite)
            .onMapTapGesture { context in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(NTMotion.spring) { points.append(context.coordinate) }
            }
            .ignoresSafeArea()

            VStack {
                header
                Spacer()
                bottomPanel
            }
        }
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            Text("Tap to lay down the path")
                .font(NTFont.mono(11, .semibold)).tracking(0.6)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(NTColor.pine.opacity(0.75)))
                .overlay(Capsule().stroke(NTColor.milk(0.18), lineWidth: 1))

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                _ = withAnimation(NTMotion.spring) { points.popLast() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(NTColor.milk(0.1)))
                    .overlay(Circle().stroke(NTColor.milk(0.22), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(points.isEmpty)
            .opacity(points.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    private func pointMarker(isLast: Bool) -> some View {
        Circle()
            .fill(isLast ? NTColor.accent : NTColor.milk)
            .frame(width: isLast ? 12 : 8, height: isLast ? 12 : 8)
            .overlay(Circle().stroke(NTColor.pine, lineWidth: 1.5))
            .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
    }

    private var bottomPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                stat(String(format: "%.2f", distanceKM), "KM", "DISTANCE")
                stat("\(points.count)", "", "POINTS")
            }

            TransportPicker(selection: $transport)

            HStack(spacing: 12) {
                Button {
                    withAnimation(NTMotion.spring) { points.removeAll() }
                } label: {
                    Text("Clear")
                        .font(NTFont.body(14, .semibold))
                        .foregroundStyle(NTColor.milk(0.7))
                        .frame(width: 90, height: 54)
                        .background(NTColor.milk(0.1), in: Capsule())
                        .overlay(Capsule().stroke(NTColor.milk(0.2), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(points.isEmpty)
                .opacity(points.isEmpty ? 0.4 : 1)

                Button {
                    finish()
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Use this path").font(NTFont.body(15, .semibold))
                    }
                    .foregroundStyle(Color(hex: 0x231007))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(NTColor.milk, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(points.count < 2)
                .opacity(points.count < 2 ? 0.4 : 1)
            }
        }
        .padding(18)
        .background(NTColor.pine.opacity(0.92), in: RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: NTRadius.sheet, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
    }

    private func stat(_ value: String, _ unit: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            (Text(value).font(NTFont.mono(20, .semibold)) + Text(unit.isEmpty ? "" : " " + unit).font(NTFont.mono(10, .medium)).foregroundStyle(NTColor.milk(0.55)))
            Text(label).font(NTFont.mono(9, .medium)).tracking(1).foregroundStyle(NTColor.milk(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func finish() {
        let trackPoints = points.map { TrackPoint(lat: $0.latitude, lng: $0.longitude) }
        onFinish(RecordResult(distanceKM: distanceKM, ascentM: 0, highPointM: 0, points: trackPoints, pois: [], transport: transport))
    }
}
