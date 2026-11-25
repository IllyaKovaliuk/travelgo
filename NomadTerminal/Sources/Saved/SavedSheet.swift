import SwiftUI

/// Saved / offline library, reached from the top of Profile now that the
/// bottom bar's slot belongs to Crews. Wraps `SavedView` unchanged.
struct SavedSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SavedView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
                .toolbarColorScheme(ThemeManager.shared.colorScheme, for: .navigationBar)
        }
        .preferredColorScheme(ThemeManager.shared.colorScheme)
    }
}
