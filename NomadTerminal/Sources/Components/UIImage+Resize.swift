import UIKit

/// Shared by every real photo-upload flow (route cover photos, avatars) —
/// was private to `RouteUploadDetailsView` until avatars needed the same
/// downscale-before-upload step.
extension UIImage {
    /// Scales down to fit within `maxDimension` on the long edge, preserving
    /// aspect ratio. A no-op if the image is already smaller.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longEdge = max(size.width, size.height)
        guard longEdge > maxDimension else { return self }
        let scale = maxDimension / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
