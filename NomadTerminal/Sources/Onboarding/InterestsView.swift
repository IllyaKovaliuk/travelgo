import SwiftUI
import Foundation

/// 02 · Onboarding — Interests
struct InterestsView: View {
    @Binding var selected: Set<Interest>
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            NTColor.pine.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        PageDots(count: 3, index: 1)
                            .revealOnAppear(delay: 0.02)

                        Text("What kind of\nground do you\ncover?")
                            .font(NTFont.heading(34, .extraBold))
                            .foregroundStyle(NTColor.milk)
                            .lineSpacing(1)
                            .padding(.top, 26)
                            .revealOnAppear(delay: 0.06)

                        Text("Pick three or more. We'll tune the feed.")
                            .font(NTFont.body(15, .light))
                            .foregroundStyle(NTColor.milk(0.6))
                            .padding(.top, 14)
                            .revealOnAppear(delay: 0.1)

                        ZStack {
                            ForEach(Array(Interest.allCases.enumerated()), id: \.element) { index, interest in
                                InterestCard(
                                    interest: interest,
                                    isSelected: selected.contains(interest),
                                    action: { toggle(interest) }
                                )
                                .position(
                                    x: interest.frame.x + interest.frame.w / 2,
                                    y: interest.frame.y + interest.frame.h / 2
                                )
                                .revealOnAppear(delay: 0.14 + Double(index) * 0.05, distance: 20)
                            }
                        }
                        .frame(width: 330, height: 470)
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                }

                footer
                    .padding(.horizontal, 30)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .background(NTColor.pine)
                    .revealOnAppear(delay: 0.5)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center) {
            Text("\(String(format: "%02d", selected.count)) SELECTED")
                .font(NTFont.mono(12, .medium))
                .tracking(1.2)
                .foregroundStyle(NTColor.milk(0.55))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: selected.count)

            Spacer()

            Button(action: onContinue) {
                HStack(spacing: 10) {
                    Text("Continue")
                        .font(NTFont.body(15, .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(NTColor.pine)
                .padding(.horizontal, 30)
                .frame(height: 56)
                .background(NTColor.milk, in: Capsule())
            }
            .buttonStyle(.plain)
            .ntPressable()
        }
    }

    private func toggle(_ interest: Interest) {
        if selected.contains(interest) {
            selected.remove(interest)
        } else {
            selected.insert(interest)
        }
    }
}

#Preview {
    InterestsView(selected: .constant([.overland, .hiking]), onContinue: {})
}
