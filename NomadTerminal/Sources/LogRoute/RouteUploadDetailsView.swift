import SwiftUI

/// 15 · Log a route — details. Real text fields feeding a draft that gets
/// published for real on the last step.
struct RouteUploadDetailsView: View {
    @Binding var draft: NewRouteDraft
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    stepHeader(title: "Route details", step: 1)

                    coverSlot

                    field(label: "TITLE") {
                        TextField("", text: $draft.title, prompt: Text("Zagar Pass at first light").foregroundStyle(NTColor.milk(0.3)))
                            .font(NTFont.heading(15, .bold))
                    }
                    .padding(.top, 18)

                    field(label: "REGION") {
                        TextField("", text: $draft.place, prompt: Text("Svaneti, Georgia").foregroundStyle(NTColor.milk(0.3)))
                            .font(NTFont.body(14.5, .medium))
                    }
                    .padding(.top, 14)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TRANSPORT").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                        HStack(spacing: 10) {
                            ForEach([Transport.overland, .foot, .water, .climb], id: \.self) { t in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    draft.transport = t
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: t.icon).font(.system(size: 18))
                                        Text(t.rawValue).font(NTFont.mono(8.5, .semibold))
                                    }
                                    .foregroundStyle(draft.transport == t ? Color(hex: 0x231007) : NTColor.milk(0.75))
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(draft.transport == t ? t.color : NTColor.milk(0.08)))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: draft.transport == t ? 0 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("DIFFICULTY").font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
                        HStack(spacing: 8) {
                            ForEach([Route.Difficulty.easy, .moderate, .hard], id: \.self) { d in
                                Button {
                                    draft.difficulty = d
                                } label: {
                                    Text(d.rawValue)
                                        .font(NTFont.mono(12.5, .semibold)).tracking(0.4)
                                        .foregroundStyle(draft.difficulty == d ? NTColor.milk : NTColor.milk(0.6))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Capsule().fill(draft.difficulty == d ? d.color : .clear))
                                        .overlay(Capsule().stroke(NTColor.milk(0.2), lineWidth: draft.difficulty == d ? 0 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.top, 18)

                    field(label: "DISTANCE (KM)") {
                        TextField("", text: $draft.distanceKM, prompt: Text("62.4").foregroundStyle(NTColor.milk(0.3)))
                            .keyboardType(.decimalPad)
                            .font(NTFont.mono(14, .semibold))
                    }
                    .padding(.top, 14)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }

            NTPrimaryButton(title: "Continue", icon: "arrow.right", action: onContinue)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 14)
                .background(NTColor.pine)
                .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .background(NTColor.pine.ignoresSafeArea())
        .foregroundStyle(NTColor.milk)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var coverSlot: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(NTColor.milk(0.05))
            .frame(height: 150)
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(NTColor.milk(0.28))
            )
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 24, weight: .light))
                    Text("Add cover photo").font(NTFont.body(12.5, .semibold))
                }
                .foregroundStyle(NTColor.milk(0.6))
            )
            .padding(.top, 20)
    }

    private func stepHeader(title: String, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(title).font(NTFont.body(15, .semibold))
                Spacer()
                Text("\(step) OF 3").font(NTFont.mono(10, .medium)).tracking(0.6).foregroundStyle(NTColor.milk(0.5))
            }
            HStack(spacing: 6) {
                ForEach(1...3, id: \.self) { i in
                    Capsule().fill(i <= step ? NTColor.milk : NTColor.milk(0.2)).frame(height: 3)
                }
            }
        }
    }

    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(NTFont.mono(10, .medium)).tracking(1.2).foregroundStyle(NTColor.milk(0.5))
            content()
                .foregroundStyle(NTColor.milk)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(NTColor.milk(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(NTColor.milk(0.16), lineWidth: 1))
        }
    }
}
