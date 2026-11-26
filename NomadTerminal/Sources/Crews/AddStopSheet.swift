import SwiftUI

/// A non-route stop for the itinerary: stay, food, activity or place.
struct AddStopSheet: View {
    @Environment(\.dismiss) private var dismiss
    let expeditionId: UUID
    let dayOptions: [Int]
    var initialDay: Int? = nil
    var onAdded: () -> Void

    @State private var kind: StopKind = .accommodation
    @State private var title = ""
    @State private var notes = ""
    @State private var day: Int?
    @State private var didSetDay = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let noteLimit = 280

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    MonoLabel("Type")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                        ForEach(StopKind.allCases) { k in
                            Button { kind = k } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: k.icon).font(.system(size: 17))
                                    Text(k.title).font(NTFont.body(14.5, .semibold)).lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .frame(maxWidth: .infinity).frame(height: 62)
                                .foregroundStyle(kind == k ? NTColor.pine : NTColor.milk(0.85))
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(kind == k ? NTColor.milk : NTColor.pineRaised))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(kind == k ? Color.clear : NTColor.pineLine, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    TextField("Name", text: $title)
                        .font(NTFont.body(16, .medium))
                        .padding(.horizontal, 16).frame(height: 54)
                        .crewCard(radius: 16)
                        .onChange(of: title) { _, new in if new.count > 120 { title = String(new.prefix(120)) } }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            MonoLabel("Note · optional")
                            Spacer()
                            Text("\(notes.count)/\(noteLimit)").font(NTFont.mono(10.5, .medium)).foregroundStyle(NTColor.milk(0.55))
                        }
                        TextField("Refill at the lake outlet…", text: $notes, axis: .vertical)
                            .font(NTFont.body(15, .regular))
                            .lineLimit(3...6)
                            .padding(16)
                            .crewCard(radius: 16)
                            .onChange(of: notes) { _, new in if new.count > noteLimit { notes = String(new.prefix(noteLimit)) } }
                    }

                    Picker("Day", selection: $day) {
                        Text("Unscheduled").tag(Int?.none)
                        ForEach(dayOptions, id: \.self) { Text("Day \($0)").tag(Int?.some($0)) }
                    }
                    .pickerStyle(.menu).tint(NTColor.accent)

                    if let errorMessage {
                        Text(errorMessage).font(NTFont.body(12.5, .medium)).foregroundStyle(NTColor.hardBright)
                    }

                    NTAccentButton(title: isSaving ? "Adding…" : (day.map { "Add to Day \($0)" } ?? "Add stop")) { add() }
                        .opacity(trimmed.isEmpty || isSaving ? 0.5 : 1)
                        .disabled(trimmed.isEmpty || isSaving)
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
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
        .onAppear { if !didSetDay { day = initialDay; didSetDay = true } }
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
