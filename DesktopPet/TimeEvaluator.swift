import Foundation

/// Adds and subtracts times, where 60 minutes make an hour: "1:45 + 2:30" is "4:15".
///
/// Each part is a length of time or a clock time:
/// - "1:45" (hours:minutes), "1:45:30" (hours:minutes:seconds), "1h 30m", "90 min", "45s", "1.5h"
/// - a plain number is minutes: "1:30 + 45" is "2:15"
/// - a clock time has AM or PM: "9am", "9:30 PM", "12:15a"
///
/// Lengths add to a length. A clock time plus or minus lengths is a clock time ("9:30am + 2:45" is
/// "12:15 PM"), and one clock time minus another is the time between them ("5pm - 9:30am" is "7:30",
/// counting overnight if the second is later).
enum TimeEvaluator {
    struct Answer: Equatable {
        /// What to show, like "4:15" or "1:00 AM +1 day".
        var text: String
        /// What to type back in to keep going, like "1:00am".
        var reuse: String
    }

    enum Failure: Error, Equatable {
        case empty
        case unfinished
        case notATime(String)
        case tooManyMinutes
        case badClock(String)
        case twoClocks
        case clockNotLength

        var message: String {
            switch self {
            case .empty: "Type some times first"
            case .unfinished: "That seems unfinished"
            case .notATime(let part): "I don't understand \"\(part)\""
            case .tooManyMinutes: "Minutes and seconds go up to 59"
            case .badClock(let part): "\"\(part)\" isn't a clock time"
            case .twoClocks: "Can't add two clock times"
            case .clockNotLength: "Type a length of time, not a clock time"
            }
        }
    }

    static func evaluate(_ text: String, military: Bool = AppPreferences.usesMilitaryTime) -> Result<Answer, Failure> {
        do {
            let parts = try split(text)
            var seconds = 0
            var clocks = 0 // +1 for each clock time added, -1 for each subtracted
            var usedClocks = false
            for (sign, part) in parts {
                let (value, isClock) = try parse(part)
                seconds += sign * value
                if isClock { clocks += sign; usedClocks = true }
            }
            switch clocks {
            case 0:
                // "5pm - 9am": if any clock times were involved, a negative gap means overnight.
                if usedClocks { seconds = ((seconds % day) + day) % day }
                let text = durationText(seconds)
                return .success(Answer(text: text, reuse: text))
            case 1:
                return .success(clockAnswer(seconds, military: military))
            default:
                throw Failure.twoClocks
            }
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.unfinished)
        }
    }

    /// A length of time in seconds, like "1:09", "1h 9m" or "45" (minutes). Sums work too; clock times don't.
    /// With `allowOverflow`, minutes and seconds can go past 59, so "5:70" is 6:10.
    static func seconds(_ text: String, allowOverflow: Bool = false) -> Result<Int, Failure> {
        do {
            var seconds = 0
            for (sign, part) in try split(text) {
                let (value, isClock) = try parse(part, allowOverflow: allowOverflow)
                if isClock { throw Failure.clockNotLength }
                seconds += sign * value
            }
            return .success(seconds)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.unfinished)
        }
    }

    private static let day = 24 * 3600

    /// Splits "1:30 + 45m - 10" into signed parts. A leading minus makes the first part negative.
    private static func split(_ text: String) throws -> [(Int, String)] {
        let normalized = text.map { c -> Character in
            switch c {
            case "−", "–": "-"
            default: c
            }
        }
        var parts: [(Int, String)] = []
        var sign = 1
        var current = ""
        func finish() throws {
            let part = current.trimmingCharacters(in: .whitespaces)
            guard !part.isEmpty else { throw Failure.unfinished }
            parts.append((sign, part))
            current = ""
        }
        for c in normalized {
            if c == "+" || c == "-" {
                if parts.isEmpty && current.trimmingCharacters(in: .whitespaces).isEmpty {
                    if c == "-" { sign = -sign } // "-1:30 + 2:00"
                    continue
                }
                try finish()
                sign = c == "+" ? 1 : -1
            } else {
                current.append(c)
            }
        }
        if parts.isEmpty && current.trimmingCharacters(in: .whitespaces).isEmpty { throw Failure.empty }
        try finish()
        return parts
    }

    /// One part, in seconds, and whether it's a clock time.
    private static func parse(_ part: String, allowOverflow: Bool = false) throws -> (Int, Bool) {
        let compact = part.lowercased().filter { !$0.isWhitespace }

        // Clock times: "9am", "9:30pm", "12:15a", "9:30 p.m."
        let noDots = compact.replacingOccurrences(of: ".", with: "")
        for (suffixes, isPM) in [(["am", "a"], false), (["pm", "p"], true)] {
            for suffix in suffixes where noDots.hasSuffix(suffix) {
                let clock = String(noDots.dropLast(suffix.count))
                let pieces = clock.split(separator: ":", omittingEmptySubsequences: false)
                guard (1...2).contains(pieces.count),
                      let hour = Int(pieces[0]), (1...12).contains(hour),
                      pieces.count == 1 || pieces[1].count == 2,
                      let minute = pieces.count == 2 ? Int(pieces[1]) : 0, (0...59).contains(minute)
                else { throw Failure.badClock(part) }
                return (((hour % 12) + (isPM ? 12 : 0)) * 3600 + minute * 60, true)
            }
        }

        // "1:45" or "1:45:30"
        if compact.contains(":") {
            let pieces = compact.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(pieces.count) else { throw Failure.notATime(part) }
            let numbers = pieces.map { $0.isEmpty ? 0 : Int($0) }
            guard numbers.allSatisfy({ $0 != nil }) else { throw Failure.notATime(part) }
            let values = numbers.map { $0! }
            guard allowOverflow || values.dropFirst().allSatisfy({ $0 < 60 }) else { throw Failure.tooManyMinutes }
            return (values[0] * 3600 + values[1] * 60 + (values.count == 3 ? values[2] : 0), false)
        }

        // A plain number is minutes.
        if let minutes = Double(compact) { return (Int((minutes * 60).rounded()), false) }

        // "1h 30m", "90min", "1.5 hours", "45s"
        var total = 0.0
        var number = ""
        var unit = ""
        var sawAny = false
        func flush() throws {
            guard !number.isEmpty || !unit.isEmpty else { return }
            guard let value = Double(number), let scale = unitScale[unit] else { throw Failure.notATime(part) }
            total += value * scale
            sawAny = true
            number = ""
            unit = ""
        }
        for c in compact {
            if c.isNumber || c == "." {
                if !unit.isEmpty { try flush() }
                number.append(c)
            } else if c.isLetter {
                unit.append(c)
            } else {
                throw Failure.notATime(part)
            }
        }
        try flush()
        guard sawAny else { throw Failure.notATime(part) }
        return (Int(total.rounded()), false)
    }

    private static let unitScale: [String: Double] = {
        var scales: [String: Double] = [:]
        for word in ["h", "hr", "hrs", "hour", "hours"] { scales[word] = 3600 }
        for word in ["m", "min", "mins", "minute", "minutes"] { scales[word] = 60 }
        for word in ["s", "sec", "secs", "second", "seconds"] { scales[word] = 1 }
        return scales
    }()

    /// "4:15", "26:00", "-0:15", or "1:02:05" when there are seconds.
    static func durationText(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : ""
        let s = abs(seconds)
        let (h, m, sec) = (s / 3600, s % 3600 / 60, s % 60)
        return sec == 0
            ? "\(sign)\(h):" + String(format: "%02d", m)
            : "\(sign)\(h):" + String(format: "%02d:%02d", m, sec)
    }

    /// "12:15 PM" (or "12:15" in military time), plus "+1 day" when it rolls past midnight.
    private static func clockAnswer(_ seconds: Int, military: Bool) -> Answer {
        let days = Int((Double(seconds) / Double(day)).rounded(.down))
        let s = seconds - days * day
        let (h, m, sec) = (s / 3600, s % 3600 / 60, s % 60)
        let secText = sec == 0 ? "" : String(format: ":%02d", sec)
        let hour12 = h % 12 == 0 ? 12 : h % 12
        let amPM = h < 12 ? "AM" : "PM"
        let clock = military
            ? String(format: "%02d:%02d", h, m) + secText
            : "\(hour12):" + String(format: "%02d", m) + secText + " \(amPM)"
        let dayNote = switch days {
        case 0: ""
        case 1: " +1 day"
        case -1: " -1 day"
        default: days > 0 ? " +\(days) days" : " \(days) days"
        }
        // Typed back in, it needs AM/PM to count as a clock time, even in military time.
        let reuse = sec == 0 ? "\(hour12):" + String(format: "%02d", m) + amPM.lowercased() : clock
        return Answer(text: clock + dayNote, reuse: reuse)
    }
}
