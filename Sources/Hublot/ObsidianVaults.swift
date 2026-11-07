import Foundation

struct ObsidianVault: Equatable {
    let name: String
    let url: URL
    /// Whether this was the vault last open in Obsidian.
    let isOpen: Bool

    /// Every Markdown note of the vault. Hidden folders such as `.obsidian` are skipped.
    func notes() -> [URL] {
        guard let files = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files.compactMap { $0 as? URL }
            .filter(SupportedFile.isMarkdown)
            .sorted { relativePath(of: $0).localizedStandardCompare(relativePath(of: $1)) == .orderedAscending }
    }

    /// The name of a note shown in the list: its path in the vault, without the extension.
    func displayName(of note: URL) -> String {
        (relativePath(of: note) as NSString).deletingPathExtension
    }

    private func relativePath(of note: URL) -> String {
        let root = url.standardizedFileURL.path
        let path = note.standardizedFileURL.path
        return path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : note.lastPathComponent
    }
}

enum ObsidianVaults {
    private struct Registry: Decodable {
        struct Entry: Decodable {
            let path: String
            let open: Bool?
        }
        let vaults: [String: Entry]
    }

    /// Reads the list of vaults that Obsidian keeps in its Application Support folder.
    static func load() -> [ObsidianVault] {
        let fileManager = FileManager.default
        guard
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
            let data = try? Data(contentsOf: support.appendingPathComponent("obsidian/obsidian.json")),
            let registry = try? JSONDecoder().decode(Registry.self, from: data)
        else { return [] }

        return registry.vaults.values
            .filter { fileManager.fileExists(atPath: $0.path) }
            .map {
                let url = URL(fileURLWithPath: $0.path, isDirectory: true)
                return ObsidianVault(name: url.lastPathComponent, url: url, isOpen: $0.open == true)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
