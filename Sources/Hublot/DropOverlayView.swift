import AppKit

/// Receives file drops over the whole window. It sits above the other views because they
/// would otherwise take the drag, and lets mouse events through to them.
final class DropOverlayView: NSView {
    var onDrop: ((URL) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard supportedFile(in: sender) != nil else { return [] }
        setHighlighted(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setHighlighted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setHighlighted(false)
        guard let file = supportedFile(in: sender) else { return false }
        onDrop?(file)
        return true
    }

    private func supportedFile(in info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        return urls?.first(where: SupportedFile.isSupported)
    }

    private func setHighlighted(_ highlighted: Bool) {
        layer?.borderWidth = highlighted ? 3 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        layer?.backgroundColor = highlighted
            ? NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            : nil
    }
}
