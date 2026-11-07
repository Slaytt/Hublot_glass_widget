import AppKit

/// A searchable list of the notes of the user's Obsidian vaults.
final class NoteBrowserView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private static let lastVaultKey = "LastObsidianVault"

    var onSelect: ((URL) -> Void)?

    private let vaultPicker = NSPopUpButton()
    private let searchField = NSSearchField()
    private let table = NSTableView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    private var vaults: [ObsidianVault] = []
    private var currentVault: ObsidianVault?
    private var allNotes: [(url: URL, name: String)] = []
    private var shownNotes: [(url: URL, name: String)] = []

    init() {
        super.init(frame: .zero)
        setUpViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    func reload() {
        vaults = ObsidianVaults.load()
        vaultPicker.removeAllItems()
        vaultPicker.addItems(withTitles: vaults.map(\.name))
        vaultPicker.isHidden = vaults.count < 2

        let lastName = UserDefaults.standard.string(forKey: Self.lastVaultKey)
        let vault = vaults.first { $0.name == lastName } ?? vaults.first(where: \.isOpen) ?? vaults.first
        guard let vault else {
            currentVault = nil
            setNotes([])
            messageLabel.stringValue = "No Obsidian vault found."
            return
        }
        vaultPicker.selectItem(withTitle: vault.name)
        load(vault)
    }

    private func load(_ vault: ObsidianVault) {
        currentVault = vault
        UserDefaults.standard.set(vault.name, forKey: Self.lastVaultKey)
        messageLabel.stringValue = "Loading…"
        setNotes([])

        // A vault can be large or stored in iCloud, which must not freeze the window.
        DispatchQueue.global(qos: .userInitiated).async {
            let notes = vault.notes().map { (url: $0, name: vault.displayName(of: $0)) }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.currentVault == vault else { return }
                self.messageLabel.stringValue = notes.isEmpty ? "No notes in this vault." : ""
                self.setNotes(notes)
            }
        }
    }

    private func setNotes(_ notes: [(url: URL, name: String)]) {
        allNotes = notes
        applySearch()
    }

    private func applySearch() {
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        shownNotes = query.isEmpty ? allNotes : allNotes.filter { $0.name.localizedStandardContains(query) }
        table.reloadData()
    }

    private func setUpViews() {
        vaultPicker.controlSize = .small
        vaultPicker.target = self
        vaultPicker.action = #selector(vaultChanged)

        searchField.placeholderString = "Search notes"
        searchField.controlSize = .small
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(searchChanged)

        let column = NSTableColumn(identifier: .init("note"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)

        let scrollView = NSScrollView()
        scrollView.documentView = table
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        table.backgroundColor = .clear

        let stack = NSStackView(views: [vaultPicker, searchField, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            vaultPicker.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
            searchField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16),
            messageLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            messageLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
        ])
    }

    @objc private func vaultChanged() {
        guard let name = vaultPicker.titleOfSelectedItem,
              let vault = vaults.first(where: { $0.name == name })
        else { return }
        load(vault)
    }

    @objc private func searchChanged() {
        applySearch()
    }

    @objc private func rowClicked() {
        guard shownNotes.indices.contains(table.clickedRow) else { return }
        onSelect?(shownNotes[table.clickedRow].url)
    }

    // Return in the search field opens the first result.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.insertNewline(_:)), let first = shownNotes.first else {
            return false
        }
        onSelect?(first.url)
        return true
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        shownNotes.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("noteCell")
        let label = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? {
                let label = NSTextField(labelWithString: "")
                label.identifier = identifier
                label.lineBreakMode = .byTruncatingHead
                return label
            }()
        label.stringValue = shownNotes[row].name
        return label
    }
}
