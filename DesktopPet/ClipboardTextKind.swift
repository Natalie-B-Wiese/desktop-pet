import AppKit
import Foundation

/// What a copied text is, when it's just one recognizable thing: a color, a link, an email address,
/// JSON, a sum, or a date or time. Anything else (or anything with more around it) is plain text.
/// Each kind has its own up-close page and list row.
enum ClipboardTextKind {
    case color(NSColor)
    case link(URL)
    case email(String)
    case json(ClipboardJSON)
    case math(answer: String, copy: String)
    case date(ClipboardDate)
    case text

    /// Checked in this order, so "#E8893A" is a color and "12/25" a date rather than 0.48.
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
        if let math = math(in: trimmed) { return .math(answer: math.answer, copy: math.copy) }
        if let date = ClipboardDate(trimmed) { return .date(date) }
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

    // MARK: - Math

    /// A sum the Math page can work out, like "1,240 * 15%" or "1:45 + 30 min". Plain numbers aren't sums,
    /// and neither are things like "555-1234", "12/25/2026" or "2026-12-25" (only `-` or `/` with no spaces).
    private static func math(in text: String) -> (answer: String, copy: String)? {
        guard text.count <= 200, !text.contains(where: \.isNewline) else { return nil }
        let operators = CharacterSet(charactersIn: "+-*/^×÷%√")
        let afterFirst = text.unicodeScalars.dropFirst() // a leading minus is just a negative number
        let used = Set(afterFirst.filter { operators.contains($0) }.map(Character.init))
        let words = ["sqrt", "abs"].contains { text.lowercased().contains($0) }
        guard !used.isEmpty || words || text.hasPrefix("√") else { return nil }
        if used.isSubset(of: ["-", "/"]), !words, !text.contains(" ") { return nil }

        if case .success(let value) = MathEvaluator.evaluate(text) {
            // Shown with commas, copied without (like clicking an answer on the Math page), so it pastes as a number.
            return (MathEvaluator.format(value, grouping: true), MathEvaluator.format(value))
        }
        // Times, only when there's a + or - between parts: "1:45 + 30 min", "5pm - 9:30am".
        if text.contains(" + ") || text.contains(" - "), case .success(let answer) = TimeEvaluator.evaluate(text) {
            return (answer.text, answer.text)
        }
        return nil
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

// MARK: - Date

/// A copied date or time on its own, like "Thursday at 2pm", "Dec 12, 2026" or "3:30 PM".
struct ClipboardDate {
    let date: Date
    /// False for a date alone, like "Dec 12" (the detector puts those at noon).
    let hasTime: Bool

    init?(_ text: String) {
        guard text.count <= 60, !text.contains(where: \.isNewline),
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        // The date has to be the whole text (a trailing "." is fine), not a date inside a sentence.
        guard let match = detector.firstMatch(in: text, range: range), let found = match.date,
              match.range.location == 0, range.length - match.range.length <= 1 else { return nil }
        // A plain number like "2026" or "15" isn't worth a date page.
        guard text.contains(where: \.isLetter) || text.contains("/") || text.contains(":") else { return nil }

        let lower = text.lowercased()
        hasTime = lower.contains(/\d\s*(am|pm|a\.m\.|p\.m\.)|\d:\d\d|noon|midnight/)
        // A time alone ("9am") means the next 9 AM, even when today's has passed.
        let timeAlone = lower.wholeMatch(of: /\s*(at\s+)?(\d{1,2}(:\d\d)?\s*(am|pm|a\.m\.|p\.m\.)?|noon|midnight)\.?\s*/) != nil
        if timeAlone, found < Date(), let next = Calendar.current.date(byAdding: .day, value: 1, to: found) {
            date = next
        } else {
            date = found
        }
    }

    /// "Thursday, Nov 12, 2026": the year only when it isn't this year.
    var dayText: String {
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        return thisYear ? date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
                        : date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }

    /// "Fri, Dec 25", or "Nov 10 · 2:30 PM" with a time (no weekday, so it fits the list's row), with the year
    /// when it isn't this year.
    var shortText: String {
        let thisYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let day = !thisYear ? date.formatted(.dateTime.month(.abbreviated).day().year())
            : hasTime ? date.formatted(.dateTime.month(.abbreviated).day())
            : date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return timeText.map { "\(day) · \($0)" } ?? day
    }

    var timeText: String? { hasTime ? AppPreferences.clockText(date) : nil }

    /// "In 2 hr 15 min", "Tomorrow", "In 3 days", "5 days ago", "Today".
    func relativeText(now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        if hasTime, abs(date.timeIntervalSince(now)) < 12 * 3600 {
            let minutes = Int((abs(date.timeIntervalSince(now)) / 60).rounded())
            let length = minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
            if minutes == 0 { return "Now" }
            return date > now ? "In \(length)" : "\(length) ago"
        }
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...: return "In \(days.formatted()) days"
        default: return "\((-days).formatted()) days ago"
        }
    }

    /// A one-time reminder goes off at the next time its clock time comes round (today, or tomorrow if it's passed),
    /// so Remind me only works when that's this date: within the next 24 hours.
    var canRemind: Bool {
        guard hasTime else { return false }
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        guard let today = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: Date()) else { return false }
        let next = today > Date() ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
        return abs(next.timeIntervalSince(date)) < 60
    }
}
