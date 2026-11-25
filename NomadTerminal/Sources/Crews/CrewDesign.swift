import SwiftUI

// Shared pieces of the Crews / Expeditions screens (nt-design handoff):
// topographic cover, avatar stack, round icon buttons, chips, segments.

/// Muted tints for covers and initials avatars; picked deterministically per id.
private enum CrewTint {
    static let covers: [(bg: Color, line: Color, tag: Color)] = [
        (Color(hex: 0x13201A), Color(hex: 0x2A4536), Color(hex: 0xA8B8AE)),
        (Color(hex: 0x141B24), Color(hex: 0x2A3A4E), Color(hex: 0xA3B1C2)),
        (Color(hex: 0x1E1813), Color(hex: 0x4A3A2C), Color(hex: 0xBFB0A0)),
    ]
    static let avatars: [Color] = [
        Color(hex: 0x4A3426), Color(hex: 0x23394A), Color(hex: 0x2D4232), Color(hex: 0x433A22), Color(hex: 0x3B2A3A),
    ]

    static func index(_ id: UUID, count: Int) -> Int {
        Int(id.uuid.0) % count
    }
}

/// A crew / trip cover: the photo when there is one, otherwise contour lines
/// on a muted tint, with the accent dot of the logo.
struct CrewCover: View {
    let id: UUID
    var url: String?
    var caption: String?

    var body: some View {
        let tint = CrewTint.covers[CrewTint.index(id, count: CrewTint.covers.count)]
        ZStack(alignment: .bottomLeading) {
            tint.bg
            if let url, !url.isEmpty {
                RouteCoverImage(url: url, tint: tint.bg)
                LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            } else {
                ContourLines(seed: Int(id.uuid.1))
                    .stroke(tint.line, lineWidth: 1.1)
                GeometryReader { geo in
                    Circle().fill(NTColor.accent)
                        .frame(width: 6, height: 6)
                        .position(x: geo.size.width * 0.72, y: geo.size.height * 0.3)
                }
            }
            if let caption {
                Text(caption.uppercased())
                    .font(NTFont.mono(10, .medium)).foregroundStyle(tint.tag)
                    .padding(.leading, 14).padding(.bottom, 10)
            }
        }
        .clipped()
    }
}

/// Stacked wavy contour lines; `seed` shifts the phase so covers differ.
struct ContourLines: Shape {
    var seed: Int
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let phase = CGFloat(seed % 7) * 6
        for i in 0..<5 {
            let y = rect.height * (0.78 - CGFloat(i) * 0.14)
            p.move(to: CGPoint(x: -10, y: y))
            p.addCurve(to: CGPoint(x: rect.width * 0.5, y: y - 24 + phase * 0.3),
                       control1: CGPoint(x: rect.width * 0.15, y: y - 30 - phase),
                       control2: CGPoint(x: rect.width * 0.3, y: y + 14))
            p.addCurve(to: CGPoint(x: rect.width + 10, y: y - 38),
                       control1: CGPoint(x: rect.width * 0.7, y: y - 62 + phase),
                       control2: CGPoint(x: rect.width * 0.88, y: y - 10))
        }
        return p
    }
}

/// Overlapping initials avatars with a "+N" tail.
struct AvatarStack: View {
    let people: [CrewPerson]
    var total: Int? = nil
    var size: CGFloat = 28
    var maxShown = 4
    var ring: Color = NTColor.pineRaised

    var body: some View {
        let shown = Array(people.prefix(maxShown))
        let extra = max(0, (total ?? people.count) - shown.count)
        HStack(spacing: -size * 0.28) {
            ForEach(shown, id: \.id) { person in
                PersonAvatar(person: person, size: size)
                    .overlay(Circle().stroke(ring, lineWidth: 2))
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(NTFont.body(size * 0.36, .semibold)).foregroundStyle(NTColor.milk(0.6))
                    .frame(width: size, height: size)
                    .background(Circle().fill(NTColor.pineElevated))
                    .overlay(Circle().stroke(ring, lineWidth: 2))
            }
        }
    }
}

/// 44pt round button used on covers and headers.
struct CircleIconButton: View {
    let icon: String
    let label: LocalizedStringKey
    var filled = false
    var action: () -> Void

    var body: some View {
        Button(action: action) { glyph }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    var glyph: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(NTColor.milk)
            .frame(width: 44, height: 44)
            .background(Circle().fill(filled ? NTColor.pineRaised : NTColor.pine.opacity(0.6)))
            .overlay(Circle().stroke(NTColor.pineLine, lineWidth: 1))
    }
}

/// Small mono capsule: PRIVATE, PLANNING, DRAFT, MODERATE…
struct StatusChip: View {
    let text: String
    var color: Color = NTColor.milk
    var icon: String? = nil
    var filled = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(text.uppercased()).font(NTFont.mono(10, .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(filled ? NTColor.pine.opacity(0.6) : .clear))
        .overlay(Capsule().stroke(filled ? NTColor.pineLine : color.opacity(0.8), lineWidth: 1))
    }
}

/// Mono caption (CREW NAME, DAY 2 …) in secondary text.
struct MonoLabel: View {
    let text: LocalizedStringKey
    var color: Color = NTColor.milk(0.55)
    init(_ text: LocalizedStringKey, color: Color = NTColor.milk(0.55)) { self.text = text; self.color = color }

    var body: some View {
        Text(text).font(NTFont.mono(10.5, .medium)).tracking(0.8).foregroundStyle(color).textCase(.uppercase)
    }
}

/// Track + milk capsule segmented control (Upcoming / Past, Overview / …).
struct CrewSegments<T: Hashable>: View {
    let items: [(value: T, title: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                let on = selection == item.value
                Button { withAnimation(NTMotion.spring) { selection = item.value } } label: {
                    Text(item.title)
                        .font(NTFont.body(13.5, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(on ? NTColor.pine : NTColor.milk(0.6))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Capsule().fill(on ? NTColor.milk : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(NTColor.pineRaised))
        .overlay(Capsule().stroke(NTColor.pineLine, lineWidth: 1))
    }
}

/// The card surface used across the screens: 18pt radius, 1pt hairline.
struct CrewCardBackground: ViewModifier {
    var radius: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .background(NTColor.pineRaised, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(NTColor.pineLine, lineWidth: 1))
    }
}

extension View {
    func crewCard(radius: CGFloat = 18) -> some View { modifier(CrewCardBackground(radius: radius)) }
}

/// Date tile (DEC / 12) for the next-trip row.
struct DateTile: View {
    let date: Date?
    var body: some View {
        VStack(spacing: 1) {
            Text(date.map { Self.month.string(from: $0).uppercased() } ?? "—")
                .font(NTFont.mono(9, .semibold)).foregroundStyle(NTColor.accent)
            Text(date.map { Self.day.string(from: $0) } ?? "")
                .font(NTFont.heading(16, .bold)).foregroundStyle(NTColor.milk)
        }
        .frame(width: 40, height: 40)
        .background(NTColor.pine, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(NTColor.pineLine, lineWidth: 1))
    }

    private static let month: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "dd"; f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
}

extension Expedition {
    /// "12–14 DEC" style range for the mono meta lines.
    var shortRange: String {
        guard let s = startDate else { return String(localized: "No dates yet").uppercased() }
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "d"
        let m = DateFormatter(); m.timeZone = TimeZone(identifier: "UTC"); m.dateFormat = "MMM"
        guard let e = endDate, e != s else { return "\(f.string(from: s)) \(m.string(from: s))".uppercased() }
        let sameMonth = m.string(from: s) == m.string(from: e)
        let head = sameMonth ? f.string(from: s) : "\(f.string(from: s)) \(m.string(from: s))"
        return "\(head)–\(f.string(from: e)) \(m.string(from: e))".uppercased()
    }

    var dayCount: Int? {
        guard let s = startDate, let e = endDate else { return nil }
        return (Calendar(identifier: .gregorian).dateComponents([.day], from: s, to: e).day ?? 0) + 1
    }

    var isPast: Bool {
        guard let e = endDate ?? startDate else { return status == .completed }
        return status == .completed || e < Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86_400)
    }
}

extension CrewPerson {
    var tint: Color { CrewTint.avatars[CrewTint.index(id, count: CrewTint.avatars.count)] }
}
