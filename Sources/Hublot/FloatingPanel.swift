import AppKit

/// A window that stays above every other one, including full-screen apps,
/// without taking the keyboard focus from the app in use.
final class FloatingPanel: NSPanel {
    private static let frameName = "HublotPanel"
    static let defaultSize = NSSize(width: 420, height: 320)
    private static let readableSize = NSSize(width: 320, height: 240)

    let reader = ReaderViewController()

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            // .nonactivatingPanel: clicking the panel does not activate Hublot.
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        // Required to be displayed in the Space of a full-screen app, and on every desktop.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false

        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        minSize = NSSize(width: 160, height: 120)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentViewController = reader
        let controls = NSTitlebarAccessoryViewController()
        controls.view = reader.makeTitlebarControls()
        controls.layoutAttribute = .trailing
        addTitlebarAccessoryViewController(controls)

        setContentSize(Self.defaultSize)
        if !setFrameUsingName(Self.frameName) {
            moveToTopRightCorner()
        }
        setFrameAutosaveName(Self.frameName)
    }

    /// Enlarges a window too small to read in, keeping its top right corner in place.
    /// A window already large enough keeps the size the user chose.
    func growToReadableSize() {
        guard frame.width < Self.readableSize.width || frame.height < Self.readableSize.height else { return }
        let width = max(frame.width, Self.readableSize.width)
        let height = max(frame.height, Self.readableSize.height)
        setFrame(
            NSRect(x: frame.maxX - width, y: frame.maxY - height, width: width, height: height),
            display: true
        )
    }

    private func moveToTopRightCorner() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let margin: CGFloat = 24
        setFrameTopLeftPoint(NSPoint(
            x: visible.maxX - frame.width - margin,
            y: visible.maxY - margin
        ))
    }
}
