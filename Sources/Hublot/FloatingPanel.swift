import AppKit

/// A window that stays above every other one, including full-screen apps,
/// without taking the keyboard focus from the app in use.
final class FloatingPanel: NSPanel {
    private static let frameName = "HublotPanel"
    private static let defaultSize = NSSize(width: 420, height: 320)

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

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        minSize = NSSize(width: 160, height: 120)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true

        contentView = Self.makePlaceholder()

        if !setFrameUsingName(Self.frameName) {
            moveToTopRightCorner()
        }
        setFrameAutosaveName(Self.frameName)
    }

    private func moveToTopRightCorner() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let margin: CGFloat = 24
        setFrameTopLeftPoint(NSPoint(
            x: visible.maxX - frame.width - margin,
            y: visible.maxY - margin
        ))
    }

    private static func makePlaceholder() -> NSView {
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active

        let label = NSTextField(labelWithString: "Hublot")
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        return background
    }
}
