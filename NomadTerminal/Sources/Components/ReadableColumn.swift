import SwiftUI

/// On a regular-width screen (iPad, the Duo's inner display) a phone layout
/// stretched edge to edge reads badly, so content sits in a centered column
/// and the rest of the screen is filled with the app background. Compact
/// width (every iPhone, iPad Slide Over) is left exactly as it was — the
/// frame is `.infinity` there, so nothing changes.
private struct ReadableColumn: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: sizeClass == .regular ? maxWidth : .infinity)
            .frame(maxWidth: .infinity)
            .background(NTColor.pine.ignoresSafeArea())
    }
}

extension View {
    func readableColumn(maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth))
    }

    /// `fullScreenCover` whose content is held to a readable column on wide
    /// screens. Pass `readable: false` for edge-to-edge map screens.
    func ntFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        readable: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            if readable { content().readableColumn() } else { content() }
        }
    }

    func ntFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        readable: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { value in
            if readable { content(value).readableColumn() } else { content(value) }
        }
    }
}
