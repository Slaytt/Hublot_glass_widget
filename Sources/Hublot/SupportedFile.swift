import Foundation
import UniformTypeIdentifiers

/// The file types Hublot can display.
enum SupportedFile {
    static let markdownExtensions: Set<String> = ["md", "markdown"]

    static var contentTypes: [UTType] {
        [.pdf] + markdownExtensions.compactMap { UTType(filenameExtension: $0) }
    }

    static func isPDF(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "pdf"
    }

    static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }

    static func isSupported(_ url: URL) -> Bool {
        isPDF(url) || isMarkdown(url)
    }
}
