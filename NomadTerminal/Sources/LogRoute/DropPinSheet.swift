import SwiftUI

/// The quick form shown when you drop a pin mid-recording — pick what kind
/// of thing this is, give it a name, optionally a note. Any number of these
/// per route, unlike segments (which describe a stretch, not a point).
struct DropPinSheet: View {
    var onSave: (POICategory, String, String) -> Void
    var onCancel: () -> Void

    @State private var category: POICategory = .other
    @State private var title: String = ""
    @State private var note: String = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    categoryGrid(title: "OUTDOOR", cases: POICategory.outdoorCases)
                    categoryGrid(title: "IN TOWN", cases: POICategory.urbanCases + [.other])

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                        TextField("", text: $title, prompt: Text(category.label).foregroundStyle(NTColor.milk(0.3)))
                            .focused($titleFocused)
                            .font(NTFont.body(14.5, .medium))
                            .foregroundStyle(NTColor.milk)
                            .padding(.horizontal, 16)
                            .frame(height: 52)
                            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOTE (OPTIONAL)").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                        TextField("", text: $note, prompt: Text("Anything worth knowing").foregroundStyle(NTColor.milk(0.3)), axis: .vertical)
                            .font(NTFont.body(13.5, .regular))
                            .foregroundStyle(NTColor.milk)
                            .lineLimit(2...3)
                            .padding(14)
                            .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
                    }

                    Button {
                        let name = title.trimmingCharacters(in: .whitespaces)
                        onSave(category, name.isEmpty ? category.label : name, note.trimmingCharacters(in: .whitespaces))
                    } label: {
                        Text("Drop pin")
                            .font(NTFont.body(15.5, .semibold))
                            .foregroundStyle(Color(hex: 0x231007))
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(NTColor.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(NTColor.pine.ignoresSafeArea())
            .foregroundStyle(NTColor.milk)
            .navigationTitle("Drop a pin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { titleFocused = true }
    }

    private func categoryGrid(title: String, cases: [POICategory]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(cases, id: \.self) { c in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        category = c
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: c.icon).font(.system(size: 18))
                            Text(c.label)
                                .font(NTFont.mono(8.5, .semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(category == c ? Color(hex: 0x231007) : NTColor.milk(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 74)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(category == c ? c.tint : NTColor.milk(0.07)))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(NTColor.milk(0.14), lineWidth: category == c ? 0 : 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
