import SwiftUI

/// A non-route stop for the itinerary: stay, food, activity or place.
struct AddStopSheet: View {
    @Environment(\.dismiss) private var dismiss
    let expeditionId: UUID
    let dayOptions: [Int]
    var onAdded: () -> Void

    @State private var kind: StopKind = .accommodation
    @State private var title = ""
    @State private var notes = ""
    @State private var day: Int?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                        ForEach(StopKind.allCases) { k in
                            Button { kind = k } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: k.icon).font(.system(size: 18))
                                    Text(k.title).font(NTFont.body(11.5, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity).frame(height: 62)
                                .foregroundStyle(kind == k ? NTColor.pine : NTColor.milk(0.8))
                                .background(RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous)
                                    .fill(kind == k ? NTColor.milk : NTColor.milk(0.07)))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField("Name", text: $title)
                        .font(NTFont.body(16, .medium))
                        .padding(.horizontal, 16).frame(height: 54)
                        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                        .onChange(of: title) { _, new in if new.count > 120 { title = String(new.prefix(120)) } }

                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .font(NTFont.body(15, .regular))
                        .lineLimit(3...6)
                        .padding(16)
                        .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: NTRadius.card, style: .continuous))
                        .onChange(of: notes) { _, new in if new.count > 2000 { notes = String(new.prefix(2000)) } }

                    Picker("Day", selection: $day) {
                        Text("Unscheduled").tag(Int?.none)
                        ForEach(dayOptions, id: \.self) { Text("Day \($0)").tag(Int?.some($0)) }
                    }
                    .pickerStyle(.menu).tint(NTColor.milk)

                    if let errorMessage {
                        Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                    }

                    NTAccentButton(title: isSaving ? "Adding…" : "Add stop") { add() }
                        .opacity(trimmed.isEmpty || isSaving ? 0.5 : 1)
                        .disabled(trimmed.isEmpty || isSaving)
                }
                .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Add stop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }

    private func add() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let n = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                try await CrewRepository.shared.addStop(expeditionId: expeditionId, kind: kind, title: trimmed,
                                                        notes: n.isEmpty ? nil : n, day: day)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
                onAdded()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
