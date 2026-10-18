import MapboxMaps

/// One place for how Nomad maps look. Default is Mapbox Standard in its
/// bright daytime preset (colorful terrain, water, forests, 3D buildings)
/// — satellite is an opt-in toggle, not the first impression, because
/// raw imagery reads dark and muddy, especially in autumn/winter.
/// Offline tiles already cover both `.standard` and `.standardSatellite`.
enum NomadMap {
    /// Time-of-day lighting, but only dims when it's actually evening.
    static var lightPreset: StandardLightPreset {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<6: return .dawn
        case 6..<20: return .day
        case 20..<22: return .dusk
        default: return .night
        }
    }

    static func style(satellite: Bool) -> MapboxMaps.MapStyle {
        satellite ? .standardSatellite(lightPreset: lightPreset) : .standard(lightPreset: lightPreset)
    }
}
