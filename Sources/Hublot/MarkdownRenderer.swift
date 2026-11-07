import Foundation
import Markdown

enum MarkdownRenderer {
    static func html(forNoteAt url: URL) throws -> String {
        let source = try String(contentsOf: url, encoding: .utf8)
        let markdown = ObsidianSyntax(noteURL: url).toCommonMark(source)
        return page(body: HTMLFormatter.format(markdown))
    }

    // Notes can hold raw HTML, and dropped files can come from anywhere. The policy stops
    // them from running anything or loading resources other than images.
    private static func page(body: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data: https:; style-src 'unsafe-inline'">
        <style>
        :root { color-scheme: light dark; }
        body { font: 14px/1.55 -apple-system, sans-serif; margin: 0; padding: 12px 16px 24px; overflow-wrap: anywhere; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.2em 0 0.5em; }
        h1 { font-size: 1.6em; } h2 { font-size: 1.35em; } h3 { font-size: 1.15em; }
        body > :first-child { margin-top: 0; }
        img { max-width: 100%; height: auto; }
        code { font: 0.9em ui-monospace, monospace; background: rgba(127, 127, 127, 0.16); padding: 0.1em 0.3em; border-radius: 4px; }
        pre { background: rgba(127, 127, 127, 0.16); padding: 10px 12px; border-radius: 6px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        blockquote { margin: 1em 0; padding: 0.1em 0 0.1em 12px; border-left: 3px solid rgba(127, 127, 127, 0.5); }
        table { border-collapse: collapse; display: block; overflow-x: auto; }
        th, td { border: 1px solid rgba(127, 127, 127, 0.4); padding: 4px 8px; }
        hr { border: 0; border-top: 1px solid rgba(127, 127, 127, 0.4); }
        </style>
        </head>
        <body>
        \(body)
        </body>
        </html>
        """
    }
}

/// Rewrites what is specific to Obsidian (front matter, `[[wikilinks]]`, `![[embeds]]`,
/// callouts and images relative to the note) into standard Markdown.
struct ObsidianSyntax {
    private static let imageTypes = [
        "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
        "webp": "image/webp", "svg": "image/svg+xml", "bmp": "image/bmp",
    ]

    // Code spans come first so that what they contain is left untouched.
    private static let inlinePattern = try! NSRegularExpression(
        pattern: #"(`+)[^\n]*?\1|(!?)\[\[([^\]\n]+)\]\]|!\[([^\]]*)\]\((<[^>\n]+>|[^)\s]+)\)"#
    )
    private static let calloutPattern = try! NSRegularExpression(
        pattern: #"^((?:\s*>)+\s*)\[!([A-Za-z-]+)\][+-]?\s*(.*)$"#
    )

    private let noteFolder: URL
    private let vaultRoot: URL?
    private let vaultFiles: VaultFiles

    init(noteURL: URL) {
        noteFolder = noteURL.deletingLastPathComponent()
        vaultRoot = Self.findVaultRoot(from: noteFolder)
        vaultFiles = VaultFiles(root: vaultRoot)
    }

    func toCommonMark(_ source: String) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        var fence: Character?
        let lines = Self.droppingFrontMatter(normalized.components(separatedBy: "\n")).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = trimmed.first, trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                if fence == nil {
                    fence = marker
                } else if fence == marker {
                    fence = nil
                }
                return line
            }
            return fence == nil ? rewriteInline(Self.rewriteCallout(line)) : line
        }
        return lines.joined(separator: "\n")
    }

    private static func droppingFrontMatter(_ lines: [String]) -> [String] {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return lines }
        return Array(lines[(end + 1)...])
    }

    private static func rewriteCallout(_ line: String) -> String {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = calloutPattern.firstMatch(in: line, range: range),
              let prefix = Range(match.range(at: 1), in: line),
              let type = Range(match.range(at: 2), in: line),
              let title = Range(match.range(at: 3), in: line)
        else { return line }
        let shown = line[title].isEmpty ? line[type].capitalized : String(line[title])
        return "\(line[prefix])**\(shown)**  "
    }

    private func rewriteInline(_ line: String) -> String {
        let text = line as NSString
        var result = ""
        var position = 0
        for match in Self.inlinePattern.matches(in: line, range: NSRange(location: 0, length: text.length)) {
            result += text.substring(with: NSRange(location: position, length: match.range.location - position))
            position = match.range.location + match.range.length

            if match.range(at: 3).location != NSNotFound {
                let isEmbed = text.substring(with: match.range(at: 2)) == "!"
                result += rewriteWikilink(text.substring(with: match.range(at: 3)), isEmbed: isEmbed)
            } else if match.range(at: 5).location != NSNotFound {
                result += rewriteImage(
                    original: text.substring(with: match.range),
                    alt: text.substring(with: match.range(at: 4)),
                    destination: text.substring(with: match.range(at: 5))
                )
            } else {
                result += text.substring(with: match.range)
            }
        }
        return result + text.substring(from: position)
    }

    private func rewriteWikilink(_ content: String, isEmbed: Bool) -> String {
        // Inside a table, Obsidian requires the separator to be written `\|`.
        let parts = content.replacingOccurrences(of: "\\|", with: "|").components(separatedBy: "|")
        let target = parts[0].trimmingCharacters(in: .whitespaces)
        let label = parts.count > 1 && !isEmbed ? parts.dropFirst().joined(separator: "|") : target
        let escapedLabel = Self.escaped(label)

        guard let file = resolve(target) else { return escapedLabel }
        if isEmbed, let image = dataURI(forImageAt: file) {
            return "![\(escapedLabel)](<\(image)>)"
        }
        return SupportedFile.isSupported(file) ? "[\(escapedLabel)](<\(file.absoluteString)>)" : escapedLabel
    }

    // The page has no access to local files, so local images are embedded in it.
    private func rewriteImage(original: String, alt: String, destination: String) -> String {
        var path = destination
        if path.hasPrefix("<") { path = String(path.dropFirst().dropLast()) }
        guard !path.contains("://"), !path.hasPrefix("data:"),
              let decoded = path.removingPercentEncoding,
              let file = resolve(decoded),
              let image = dataURI(forImageAt: file)
        else { return original }
        return "![\(alt)](<\(image)>)"
    }

    private func dataURI(forImageAt file: URL) -> String? {
        guard let type = Self.imageTypes[file.pathExtension.lowercased()],
              let data = try? Data(contentsOf: file)
        else { return nil }
        return "data:\(type);base64,\(data.base64EncodedString())"
    }

    /// Finds a file the way Obsidian does: from the vault root or the note's folder first,
    /// then by name anywhere in the vault, preferring the shortest path.
    private func resolve(_ target: String) -> URL? {
        let path = target.components(separatedBy: "#")[0]
        guard !path.isEmpty else { return nil }

        let fileManager = FileManager.default
        let folders = [vaultRoot, noteFolder].compactMap { $0 }
        for candidate in [path, path + ".md"] {
            for folder in folders {
                let file = folder.appendingPathComponent(candidate).standardizedFileURL
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue {
                    return file
                }
            }
        }
        return vaultFiles.find(path) ?? vaultFiles.find(path + ".md")
    }

    private static func findVaultRoot(from folder: URL) -> URL? {
        var current = folder.standardizedFileURL
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".obsidian").path) {
                return current
            }
            current.deleteLastPathComponent()
        }
        return nil
    }

    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\`*_[]<>".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}

/// The files of a vault, listed once and only if a link needs them.
private final class VaultFiles {
    private let root: URL?
    private lazy var paths: [String] = {
        guard let root, let files = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.compactMap { ($0 as? URL)?.standardizedFileURL.path }
    }()

    init(root: URL?) {
        self.root = root
    }

    func find(_ relativePath: String) -> URL? {
        let suffix = "/" + relativePath.lowercased()
        return paths
            .filter { $0.lowercased().hasSuffix(suffix) }
            .min { $0.count < $1.count }
            .map { URL(fileURLWithPath: $0) }
    }
}
