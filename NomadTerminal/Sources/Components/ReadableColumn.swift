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

/// Swipe in from the left edge to go back — what `NavigationStack` pushes
/// already do, for the full-screen covers that draw their own back button.
/// Only a drag that starts at the edge and is mostly horizontal counts, so
/// scrolling and taps are untouched.
private struct EdgeSwipeBack: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                guard value.startLocation.x < 28,
                      value.translation.width > 80,
                      abs(value.translation.height) < value.translation.width * 0.5 else { return }
                dismiss()
            }
        )
    }
}

extension View {
    func edgeSwipeBack() -> some View { modifier(EdgeSwipeBack()) }

    func readableColumn(maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableColumn(maxWidth: maxWidth))
    }

    /// `fullScreenCover` whose content is held to a readable column on wide
    /// screens. Pass `readable: false` for edge-to-edge map screens.
    func ntFullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        readable: Bool = true,
        edgeSwipeBack: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            let view = readable ? AnyView(content().readableColumn()) : AnyView(content())
            if edgeSwipeBack { view.edgeSwipeBack() } else { view }
        }
    }

    func ntFullScreenCover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        readable: Bool = true,
        edgeSwipeBack: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        fullScreenCover(item: item, onDismiss: onDismiss) { value in
            let view = readable ? AnyView(content(value).readableColumn()) : AnyView(content(value))
            if edgeSwipeBack { view.edgeSwipeBack() } else { view }
        }
    }
}
