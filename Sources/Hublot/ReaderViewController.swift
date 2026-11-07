import AppKit
import PDFKit
import WebKit

/// The content of the panel: a PDF, a Markdown note, the list of Obsidian notes, or a
/// message when there is nothing to show.
final class ReaderViewController: NSViewController, WKNavigationDelegate {
    private enum Mode {
        case message, pdf, markdown, notes
    }

    private static let emptyMessage = "Drop a PDF or Markdown file here"

    private let pdfView = ZoomablePDFView()
    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private let noteBrowser = NoteBrowserView()
    private let messageLabel = NSTextField(wrappingLabelWithString: emptyMessage)
    private let backButton = ReaderViewController.makeButton("chevron.left", label: "Back")
    private let zoomOutButton = ReaderViewController.makeButton("minus.magnifyingglass", label: "Zoom Out")
    private let zoomInButton = ReaderViewController.makeButton("plus.magnifyingglass", label: "Zoom In")
    private let fitButton = ReaderViewController.makeButton("arrow.left.and.right", label: "Fit to Width")

    private var titlebarControls: NSStackView?
    private var isHoverActivated = false
    private var appBeforeHover: NSRunningApplication?
    private var isChoosingFile = false

    private var mode = Mode.message
    private var currentFile: URL?
    private var history: [URL] = []
    // Discards a file that finishes loading after another one was requested.
    private var loadID = 0
    // Only the page Hublot loads itself may navigate without a click on a link.
    private var allowsNextNavigation = false

    override func loadView() {
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: FloatingPanel.defaultSize))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        view = background
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pdfView.displayMode = .singlePageContinuous
        pdfView.autoScales = true
        webView.navigationDelegate = self
        noteBrowser.onSelect = { [weak self] in self?.open($0) }
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor

        // These views take drags for themselves, which would hide them from the overlay.
        pdfView.unregisterDraggedTypes()
        webView.unregisterDraggedTypes()

        let overlay = DropOverlayView()
        overlay.onDrop = { [weak self] in self?.open($0) }

        let guide = view.safeAreaLayoutGuide
        for content in [pdfView, webView, noteBrowser, overlay] as [NSView] {
            content.translatesAutoresizingMaskIntoConstraints = false
        }
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        // The overlay comes last to stay on top.
        for content in [pdfView, webView, noteBrowser, messageLabel, overlay] as [NSView] {
            view.addSubview(content)
        }
        for content in [pdfView, webView, noteBrowser, overlay] as [NSView] {
            NSLayoutConstraint.activate([
                content.topAnchor.constraint(equalTo: guide.topAnchor),
                content.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
                content.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            ])
        }
        NSLayoutConstraint.activate([
            messageLabel.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),
        ])

        show(.message)
        setUpPinchToZoom()
    }

    // Caught before it reaches the views, so that the zoom follows the fingers.
    private func setUpPinchToZoom() {
        view.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
        NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
            guard let self, self.mode == .pdf, event.window === self.view.window else { return event }
            self.pdfView.zoom(
                byMagnification: event.magnification,
                around: self.pdfView.convert(event.locationInWindow, from: nil)
            )
            return nil
        }
    }

    override func mouseEntered(with event: NSEvent) {
        updateHoverActivation()
    }

    override func mouseExited(with event: NSEvent) {
        updateHoverActivation()
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        endHoverActivation()
    }

    // macOS only sends trackpad pinches to the active app, which a panel like this one
    // never becomes by itself. So the app is active while the cursor is over a PDF, and
    // the app in use gets the focus back when the cursor leaves.
    private func updateHoverActivation() {
        guard !isChoosingFile else { return }
        let isOverPDF = mode == .pdf && view.window?.frame.contains(NSEvent.mouseLocation) == true
        guard isOverPDF else { return endHoverActivation() }

        let frontmost = NSWorkspace.shared.frontmostApplication
        guard !isHoverActivated, frontmost != .current else { return }
        isHoverActivated = true
        appBeforeHover = frontmost
        NSApp.activate(ignoringOtherApps: true)
        view.window?.makeKey()
    }

    private func endHoverActivation() {
        guard isHoverActivated else { return }
        isHoverActivated = false
        // If the user clicked in another app in the meantime, it already has the focus.
        if NSApp.isActive {
            appBeforeHover?.activate(options: [])
        }
        appBeforeHover = nil
    }

    /// The buttons shown in the title bar of the panel.
    func makeTitlebarControls() -> NSView {
        backButton.target = self
        backButton.action = #selector(goBack)

        zoomOutButton.target = self
        zoomOutButton.action = #selector(zoomOut)
        zoomInButton.target = self
        zoomInButton.action = #selector(zoomIn)
        fitButton.target = self
        fitButton.action = #selector(fitToWidth)

        let notesButton = Self.makeButton("books.vertical", label: "Obsidian Notes")
        notesButton.target = self
        notesButton.action = #selector(toggleNotes)

        let openButton = Self.makeButton("folder", label: "Open File")
        openButton.target = self
        openButton.action = #selector(chooseFile)

        let stack = NSStackView(views: [
            backButton, zoomOutButton, zoomInButton, fitButton, notesButton, openButton,
        ])
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 6)
        titlebarControls = stack
        updateTitlebarControls()
        return stack
    }

    // The title bar does not resize its accessory view when a button appears or disappears.
    private func updateTitlebarControls() {
        backButton.isHidden = history.isEmpty
        for button in [zoomOutButton, zoomInButton, fitButton] {
            button.isHidden = mode != .pdf
        }
        guard let titlebarControls else { return }
        // The height is the one given by the title bar, once it has laid out the view.
        let fitting = titlebarControls.fittingSize
        titlebarControls.setFrameSize(NSSize(
            width: fitting.width,
            height: max(titlebarControls.frame.height, fitting.height)
        ))
    }

    func open(_ file: URL, recordingHistory: Bool = true) {
        guard SupportedFile.isSupported(file) else { return }

        if recordingHistory, let currentFile, currentFile != file {
            history.append(currentFile)
        }
        currentFile = file
        updateTitlebarControls()
        view.window?.title = file.deletingPathExtension().lastPathComponent
        (view.window as? FloatingPanel)?.growToReadableSize()
        loadID += 1
        let id = loadID

        // Files stored in iCloud may have to be downloaded first.
        DispatchQueue.global(qos: .userInitiated).async {
            if SupportedFile.isPDF(file) {
                let document = PDFDocument(url: file)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadID == id else { return }
                    self.display(pdf: document)
                }
            } else {
                let html = try? MarkdownRenderer.html(forNoteAt: file)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.loadID == id else { return }
                    self.display(html: html, folder: file.deletingLastPathComponent())
                }
            }
        }
    }

    private func display(pdf document: PDFDocument?) {
        guard let document else {
            return showError("This PDF could not be opened.")
        }
        guard !document.isLocked else {
            return showError("This PDF is protected by a password.")
        }
        pdfView.document = document
        // Each document starts at the width of the window, whatever the zoom of the previous one.
        pdfView.autoScales = true
        show(.pdf)
    }

    private func display(html: String?, folder: URL) {
        guard let html else {
            return showError("This file could not be read as text.")
        }
        allowsNextNavigation = true
        webView.loadHTMLString(html, baseURL: folder)
        show(.markdown)
    }

    private func showError(_ message: String) {
        messageLabel.stringValue = message
        show(.message)
    }

    private func show(_ newMode: Mode) {
        mode = newMode
        pdfView.isHidden = newMode != .pdf
        webView.isHidden = newMode != .markdown
        noteBrowser.isHidden = newMode != .notes
        messageLabel.isHidden = newMode != .message
        updateTitlebarControls()
        updateHoverActivation()
    }

    @objc private func zoomOut() {
        pdfView.zoomOut(nil)
    }

    @objc private func zoomIn() {
        pdfView.zoomIn(nil)
    }

    @objc private func fitToWidth() {
        pdfView.autoScales = true
    }

    @objc private func goBack() {
        guard let previous = history.popLast() else { return }
        open(previous, recordingHistory: false)
    }

    @objc func toggleNotes() {
        if mode == .notes, currentFile != nil {
            // The file displayed before the list is still loaded in its view.
            show(currentFile.map(SupportedFile.isPDF) == true ? .pdf : .markdown)
            view.window?.title = currentFile?.deletingPathExtension().lastPathComponent ?? ""
        } else if mode != .notes {
            showNotes()
        }
    }

    func showNotes() {
        view.window?.title = "Obsidian"
        (view.window as? FloatingPanel)?.growToReadableSize()
        noteBrowser.reload()
        show(.notes)
    }

    /// Shows the system file dialog, the only part of Hublot that has to take the focus.
    /// It is given back to the previous app afterwards.
    @objc func chooseFile() {
        let previousApp = appBeforeHover ?? NSWorkspace.shared.frontmostApplication
        // Moving the cursor off the window must not take the focus away from the dialog.
        isChoosingFile = true
        isHoverActivated = false
        appBeforeHover = nil
        let dialog = NSOpenPanel()
        dialog.allowedContentTypes = SupportedFile.contentTypes
        dialog.level = .modalPanel
        dialog.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        NSApp.activate(ignoringOtherApps: true)
        dialog.begin { [weak self] response in
            self?.isChoosingFile = false
            if response == .OK, let file = dialog.url {
                self?.open(file)
            }
            previousApp?.activate(options: [])
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if allowsNextNavigation {
            allowsNextNavigation = false
            return decisionHandler(.allow)
        }
        decisionHandler(.cancel)
        if action.navigationType == .linkActivated, let url = action.request.url {
            followLink(url)
        }
    }

    private func followLink(_ url: URL) {
        if url.isFileURL {
            // Rebuilt from the path to drop any #heading part of the link.
            let file = URL(fileURLWithPath: url.path)
            if FileManager.default.fileExists(atPath: file.path) {
                open(file)
            }
        } else if ["http", "https", "mailto"].contains(url.scheme?.lowercased()) {
            NSWorkspace.shared.open(url)
        }
    }

    private static func makeButton(_ symbol: String, label: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage()
        let button = NSButton(image: image, target: nil, action: nil)
        button.isBordered = false
        button.toolTip = label
        return button
    }
}
