import SwiftUI

/// Create (or edit) a trip: inside a crew when `crewId` is set, ad hoc
/// otherwise. `create_expedition` / `update_expedition` enforce who may.
struct CreateExpeditionView: View {
    @Environment(\.dismiss) private var dismiss
    var crewId: UUID?
    var editing: Expedition?
    var onSaved: (UUID) -> Void

    @State private var name = ""
    @State private var tripType: TripType = .roadTrip
    @State private var hasDates = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var status: ExpeditionStatus = .planning
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        label("NAME")
                        TextField("Carpathians, December", text: $name)
                            .font(NTFont.body(16, .medium))
                            .padding(.horizontal, 16)
                            .frame(height: 54)
                            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                            .onChange(of: name) { _, new in if new.count > 80 { name = String(new.prefix(80)) } }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        label("TRIP TYPE")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                            ForEach(TripType.allCases) { type in
                                Button { tripType = type } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: type.icon).font(.system(size: 18))
                                        Text(type.title).font(NTFont.body(12, .semibold))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 64)
                                    .foregroundStyle(tripType == type ? NTColor.pine : NTColor.milk(0.8))
                                    .background(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                                        .fill(tripType == type ? NTColor.milk : NTColor.milk(0.07)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Set dates", isOn: $hasDates).tint(NTColor.accent)
                            .font(NTFont.body(15, .semibold))
                        if hasDates {
                            DatePicker("Start", selection: $start, displayedComponents: .date)
                                .onChange(of: start) { _, new in if end < new { end = new } }
                            DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
                        }
                    }
                    .padding(16)
                    .background(NTColor.milk(0.05), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))

                    if editing != nil {
                        VStack(alignment: .leading, spacing: 8) {
                            label("STATUS")
                            Picker("Status", selection: $status) {
                                Text("Planning").tag(ExpeditionStatus.planning)
                                Text("Active").tag(ExpeditionStatus.active)
                                Text("Completed").tag(ExpeditionStatus.completed)
                                Text("Cancelled").tag(ExpeditionStatus.cancelled)
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                    }

                    NTAccentButton(title: isSaving ? "Saving…" : (editing == nil ? "Create trip" : "Save changes")) { save() }
                        .opacity(trimmed.isEmpty || isSaving ? 0.5 : 1)
                        .disabled(trimmed.isEmpty || isSaving)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle(editing == nil ? "New trip" : "Edit trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
        .onAppear {
            guard let e = editing else { return }
            name = e.name; tripType = e.tripType; status = e.status
            if let s = e.startDate { hasDates = true; start = s; end = e.endDate ?? s }
        }
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key).font(NTFont.mono(10.5, .medium)).tracking(0.8).foregroundStyle(NTColor.milk(0.5))
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let s = hasDates ? start : nil
                let e = hasDates ? end : nil
                let id: UUID
                if let editing {
                    try await CrewRepository.shared.updateExpedition(id: editing.id, name: trimmed, tripType: tripType,
                                                                     start: s, end: e, status: status)
                    id = editing.id
                } else {
                    id = try await CrewRepository.shared.createExpedition(name: trimmed, crewId: crewId, tripType: tripType,
                                                                          start: s, end: e)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onSaved(id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
