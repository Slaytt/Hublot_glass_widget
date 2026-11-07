import PDFKit

final class ZoomablePDFView: PDFView {
    /// Zooms by a trackpad magnification, keeping the point under the fingers in place.
    func zoom(byMagnification magnification: CGFloat, around location: NSPoint) {
        guard let page = page(for: location, nearest: true) else { return }
        let pagePoint = convert(location, to: page)

        autoScales = false
        scaleFactor *= 1 + magnification
        layoutDocumentView()

        guard let clipView = documentView?.enclosingScrollView?.contentView else { return }
        let target = clipView.convert(location, from: self)
        let current = clipView.convert(convert(pagePoint, from: page), from: self)
        clipView.scroll(to: NSPoint(
            x: clipView.bounds.origin.x + current.x - target.x,
            y: clipView.bounds.origin.y + current.y - target.y
        ))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
    }
}
