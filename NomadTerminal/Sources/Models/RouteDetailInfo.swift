import SwiftUI

/// The richer payload shown on the Route Detail screen — requirements,
/// elevation profile, segments, author's note. Mirrors "05 · Route detail".
struct RouteDetailInfo {
    let coordinates: String
    let season: String
    let duration: String
    let ascentM: Int
    let highPointM: Int
    let elevationProfile: [Double]  // normalized 0...1 samples, left to right
    let elevationPeakLabel: String
    let quote: String
    let quoteAuthor: String
    let requirements: [Requirement]
    let segments: [Segment]
    /// The real recorded GPS polyline, if this route was logged with a live
    /// CoreLocation recording. Empty for the mock routes and for anything
    /// published before real recording existed — the map header falls back
    /// to the decorative illustration when this is empty.
    let trackPoints: [TrackPoint]

    init(
        coordinates: String, season: String, duration: String, ascentM: Int, highPointM: Int,
        elevationProfile: [Double], elevationPeakLabel: String, quote: String, quoteAuthor: String,
        requirements: [Requirement], segments: [Segment], trackPoints: [TrackPoint] = []
    ) {
        self.coordinates = coordinates
        self.season = season
        self.duration = duration
        self.ascentM = ascentM
        self.highPointM = highPointM
        self.elevationProfile = elevationProfile
        self.elevationPeakLabel = elevationPeakLabel
        self.quote = quote
        self.quoteAuthor = quoteAuthor
        self.requirements = requirements
        self.segments = segments
        self.trackPoints = trackPoints
    }

    struct Requirement: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let subtitle: String
        let tint: Color
    }

    struct Segment: Identifiable {
        let id = UUID()
        let icon: String
        let name: String
        let distanceKM: Double
        let tint: Color
    }
}

extension RouteDetailInfo {
    static let zagarPass = RouteDetailInfo(
        coordinates: "SVANETI · 42.68°N 43.02°E",
        season: "JUN – OCT",
        duration: "2 DAYS",
        ascentM: 1840,
        highPointM: 2410,
        elevationProfile: [0.42, 0.38, 0.55, 0.5, 0.7, 0.66, 0.82, 0.78, 0.95, 0.9, 1.0, 0.86, 0.72, 0.6],
        elevationPeakLabel: "2410 M",
        quote: "Leave Mestia before four. The pass holds cloud until the sun clears the Ushba ridge, and once it does you get about forty minutes of the light everyone comes here for.",
        quoteAuthor: "— TAMAR MELADZE, LOGGED SEP 2025",
        requirements: [
            .init(icon: "car.side", title: "High-clearance 4×4, locked diff", subtitle: "NO SOFT-ROADERS PAST WP2", tint: NTColor.accentDeep),
            .init(icon: "drop.fill", title: "6 L water per person", subtitle: "LAST SPRING AT KM 21", tint: NTColor.water),
            .init(icon: "cloud.rain.fill", title: "Impassable after heavy rain", subtitle: "CHECK FORD AT WP3 · 48H RULE", tint: NTColor.hard),
            .init(icon: "doc.text.fill", title: "Border-zone permit required", subtitle: "FREE · 3 DAYS LEAD TIME", tint: NTColor.sage)
        ],
        segments: [
            .init(icon: Transport.foot.icon, name: "Mestia → Zhabeshi trail", distanceKM: 14.2, tint: NTColor.sage),
            .init(icon: Transport.overland.icon, name: "Ushguli track, 4×4 only", distanceKM: 31.6, tint: NTColor.accent),
            .init(icon: Transport.water.icon, name: "Enguri ford crossing", distanceKM: 0.4, tint: NTColor.water),
            .init(icon: Transport.climb.icon, name: "Zagar scramble to col", distanceKM: 16.2, tint: NTColor.extreme)
        ],
        trackPoints: [
            .init(lat: 42.640, lng: 42.980), .init(lat: 42.652, lng: 42.994), .init(lat: 42.661, lng: 43.006),
            .init(lat: 42.670, lng: 43.018), .init(lat: 42.680, lng: 43.022), .init(lat: 42.689, lng: 43.032),
            .init(lat: 42.696, lng: 43.041)
        ]
    )

    static let emeraldCorridor = RouteDetailInfo(
        coordinates: "SOČA VALLEY · 46.24°N 13.62°E",
        season: "MAY – SEP",
        duration: "1 DAY",
        ascentM: 120,
        highPointM: 480,
        elevationProfile: [0.5, 0.48, 0.6, 0.55, 0.5, 0.62, 0.58, 0.44, 0.4, 0.5, 0.46, 0.38],
        elevationPeakLabel: "480 M",
        quote: "Put in above the gorge at first light — the glacial melt keeps flow predictable until early afternoon.",
        quoteAuthor: "— LUKA KRANJC, LOGGED JUL 2025",
        requirements: [
            .init(icon: "figure.pool.swim", title: "Grade III whitewater experience", subtitle: "NOT FOR FIRST-TIMERS", tint: NTColor.water),
            .init(icon: "thermometer.snowflake", title: "Drysuit below 12°C", subtitle: "GLACIAL MELT, YEAR-ROUND COLD", tint: NTColor.extreme)
        ],
        segments: [
            .init(icon: Transport.water.icon, name: "Put-in to gorge narrows", distanceKM: 8.4, tint: NTColor.water),
            .init(icon: Transport.water.icon, name: "Gorge run to take-out", distanceKM: 10.5, tint: NTColor.water)
        ],
        trackPoints: [
            .init(lat: 46.218, lng: 13.598), .init(lat: 46.228, lng: 13.609), .init(lat: 46.240, lng: 13.620),
            .init(lat: 46.251, lng: 13.631), .init(lat: 46.262, lng: 13.641)
        ]
    )

    static let naranjoNorthFace = RouteDetailInfo(
        coordinates: "PICOS DE EUROPA · 43.19°N 4.85°W",
        season: "JUN – SEP",
        duration: "1–2 DAYS",
        ascentM: 540,
        highPointM: 2519,
        elevationProfile: [0.2, 0.3, 0.35, 0.5, 0.48, 0.62, 0.7, 0.66, 0.82, 0.9, 0.95, 1.0],
        elevationPeakLabel: "2519 M",
        quote: "The crux pitch faces north and stays wet after rain for two full days — check the topo forum before you commit.",
        quoteAuthor: "— AINARA RUIZ, LOGGED AUG 2025",
        requirements: [
            .init(icon: "figure.climbing", title: "Trad rack to 3in, double ropes", subtitle: "12 PITCHES, NO FIXED GEAR", tint: NTColor.extreme),
            .init(icon: "tent.fill", title: "Bivy gear for the col", subtitle: "MOST PARTIES SPLIT OVER 2 DAYS", tint: NTColor.gold)
        ],
        segments: [
            .init(icon: Transport.foot.icon, name: "Approach to base of wall", distanceKM: 3.1, tint: NTColor.sage),
            .init(icon: Transport.climb.icon, name: "North face, 12 pitches", distanceKM: 0.54, tint: NTColor.extreme)
        ],
        trackPoints: [.init(lat: 43.188, lng: -4.852), .init(lat: 43.191, lng: -4.848)]
    )
}
