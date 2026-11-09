import AppKit
import Foundation

/// What a copied text is, when it's just one recognizable thing: a color, a link, an email address or JSON.
/// Anything else (or anything with more around it) is plain text. Each kind has its own up-close page and list row.
/// Each is recognized by a clear rule (a `#`, `https://`, an `@`, valid JSON), never a guess.
enum ClipboardTextKind {
    case color(NSColor)
    case link(URL)
    case email(String)
    case json(ClipboardJSON)
    case text

    /// Checked in this order.
    static func of(_ text: String) -> ClipboardTextKind {
        if let cached = cache[text] { return cached }
        let kind = classify(text)
        if cache.count > 50 { cache.removeAll() } // only a handful of slots, so this rarely fills up
        cache[text] = kind
        return kind
    }

    private static var cache: [String: ClipboardTextKind] = [:]

    private static func classify(_ text: String) -> ClipboardTextKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let color = BubbleClipboardPage.hexColor(in: trimmed) { return .color(color) }
        if let url = BubbleClipboardPage.link(in: trimmed) { return .link(url) }
        if let email = email(in: trimmed) { return .email(email) }
        if let json = ClipboardJSON(trimmed) { return .json(json) }
        return .text
    }

    // MARK: - Email

    /// "natalie@example.com", or a `mailto:` link to one. One address only, nothing around it.
    private static func email(in text: String) -> String? {
        let address = text.lowercased().hasPrefix("mailto:") ? String(text.dropFirst(7)) : text
        guard address.count <= 254,
              address.wholeMatch(of: /[A-Za-z0-9._%+'-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/) != nil else { return nil }
        return address
    }
}

// MARK: - JSON

/// Copied JSON: an object or a list, tidied with each item on its own line, keeping its own order.
struct ClipboardJSON {
    /// Indented two spaces, one item per line.
    let tidied: String
    /// All on one line, with no spaces outside strings.
    let oneLine: String
    /// "Object · 4 keys" or "List · 3 items".
    let summary: String

    init?(_ text: String) {
        guard let first = text.first, first == "{" || first == "[", text.utf8.count <= 1_000_000,
              let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let object = value as? [String: Any] {
            summary = "Object · \(object.count.formatted()) \(object.count == 1 ? "key" : "keys")"
        } else if let list = value as? [Any] {
            summary = "List · \(list.count.formatted()) \(list.count == 1 ? "item" : "items")"
        } else {
            return nil
        }
        (tidied, oneLine) = Self.reformat(text)
    }

    /// Re-lays out the text itself rather than JSONSerialization's output, which would shuffle the keys.
    private static func reformat(_ text: String) -> (tidied: String, oneLine: String) {
        var tidied = ""
        var oneLine = ""
        var depth = 0
        var inString = false
        var escaped = false
        let characters = Array(text)
        func newline() { tidied += "\n" + String(repeating: "  ", count: depth) }

        for (index, c) in characters.enumerated() {
            if inString {
                tidied.append(c)
                oneLine.append(c)
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
                continue
            }
            if c.isWhitespace { continue }
            oneLine.append(c)
            switch c {
            case "\"":
                inString = true
                tidied.append(c)
            case "{", "[":
                tidied.append(c)
                depth += 1
                // "{}" and "[]" stay together.
                let next = characters[(index + 1)...].first { !$0.isWhitespace }
                if next != "}" && next != "]" { newline() }
            case "}", "]":
                depth -= 1
                let previous = characters[..<index].last { !$0.isWhitespace }
                if previous != "{" && previous != "[" { newline() }
                tidied.append(c)
            case ",":
                tidied.append(c)
                newline()
            case ":":
                tidied += ": "
            default:
                tidied.append(c)
            }
        }
        return (tidied, oneLine)
    }
}
