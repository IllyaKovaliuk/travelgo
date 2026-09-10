import SwiftUI

/// Edit a *published* route's segments and requirements — the log-a-route
/// flow could only ever set these at publish time; this closes that gap.
/// RLS already allowed owner writes on both tables from day one ("Owners
/// manage their route's segments/requirements"), so this was purely a
/// missing screen, not a missing backend capability. Same builder-list UX
/// as `RouteUploadDetailsView`'s segments/requirements sections, adapted to
/// local `@State` and seeded from the route's current real data instead of
/// a fresh draft.
struct EditRouteExtrasView: View {
    let routeId: String
    var onSaved: (Route) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var segments: [DraftSegment]
    @State private var requirements: [DraftRequirement]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(routeId: String, segments: [RouteDetailInfo.Segment], requirements: [RouteDetailInfo.Requirement], onSaved: @escaping (Route) -> Void) {
        self.routeId = routeId
        self.onSaved = onSaved
        let transports: [Transport] = [.overland, .foot, .water, .climb]
        _segments = State(initialValue: segments.map { seg in
            var d = DraftSegment()
            d.transport = transports.first(where: { $0.icon == seg.icon }) ?? .foot
            d.name = seg.name
            d.distanceKM = String(format: "%.1f", seg.distanceKM)
            return d
        })
        _requirements = State(initialValue: requirements.map { req in
            var d = DraftRequirement()
            d.category = RequirementCategory.allCases.first(where: { $0.icon == req.icon }) ?? .gear
            d.title = req.title
            d.subtitle = req.subtitle
            return d
        })
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    segmentsSection
                    requirementsSection
                    if let errorMessage {
                        Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                    }
                }
                .padding(20)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Edit route details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { save() }
                        .disabled(isSaving)
                }
            }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }

    private var segmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SEGMENTS").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                Spacer()
                addButton { segments.append(DraftSegment()) }
            }
            ForEach($segments) { $segment in
                HStack(spacing: 10) {
                    Menu {
                        ForEach([Transport.overland, .foot, .water, .climb], id: \.self) { t in
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
                    removeButton { segments.removeAll { $0.id == segment.id } }
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
                Text("REQUIREMENTS & GEAR").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                Spacer()
                addButton { requirements.append(DraftRequirement()) }
            }
            ForEach($requirements) { $req in
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
                        removeButton { requirements.removeAll { $0.id == req.id } }
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

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let updated = try await RouteRepository.shared.updateRouteExtras(
                    routeId: routeId,
                    segments: segments
                        .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
                        .map { .init(icon: $0.transport.icon, name: $0.name, distanceKM: Double($0.distanceKM.replacingOccurrences(of: ",", with: ".")) ?? 0, tint: $0.transport.dbHex) },
                    requirements: requirements
                        .filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                        .map { .init(icon: $0.category.icon, title: $0.title, subtitle: $0.subtitle, tint: $0.category.dbHex) }
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                onSaved(updated)
                dismiss()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = "Couldn't save — check your connection and try again."
            }
            isSaving = false
        }
    }
}
