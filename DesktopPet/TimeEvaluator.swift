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
///
/// A part can also be a date: "today", "tomorrow", "yesterday", a weekday ("fri" is the coming Friday,
/// or today if it's Friday), "Dec 25" or "12/25" (the nearest one, so in October "Jan 5" is next
/// January), with an optional year ("Dec 25 2027", "12/25/27"). Lengths can be days and weeks ("90d",
/// "2w 3d"). A date plus or minus whole days is a date, and one date minus another is the days between
/// them. Dates and clock times don't mix yet.
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
        case badDate(String)
        case twoDates
        case dateAndClock
        case partialDays
        case dateNotLength

        var message: String {
            switch self {
            case .empty: "Type some times first"
            case .unfinished: "That seems unfinished"
            case .notATime(let part): "I don't understand \"\(part)\""
            case .tooManyMinutes: "Minutes and seconds go up to 59"
            case .badClock(let part): "\"\(part)\" isn't a clock time"
            case .twoClocks: "Can't add two clock times"
            case .clockNotLength: "Type a length of time, not a clock time"
            case .badDate(let part): "\"\(part)\" isn't a real date"
            case .twoDates: "Can't add two dates"
            case .dateAndClock: "Can't mix dates and clock times yet"
            case .partialDays: "Add whole days to a date, like 90d"
            case .dateNotLength: "Type a length of time, not a date"
            }
        }
    }

    static func evaluate(_ text: String, military: Bool = AppPreferences.usesMilitaryTime,
                         now: Date = Date()) -> Result<Answer, Failure> {
        do {
            let parts = try split(text)
            let today = dayNumber(of: now)
            var seconds = 0
            var clocks = 0 // +1 for each clock time added, -1 for each subtracted
            var usedClocks = false
            var dateDays = 0 // the dates' day numbers, added and subtracted
            var dates = 0 // like `clocks`, for dates
            var usedDates = false
            for (sign, part) in parts {
                let (value, kind) = try parse(part, today: today)
                switch kind {
                case .length:
                    seconds += sign * value
                case .clock:
                    seconds += sign * value
                    clocks += sign
                    usedClocks = true
                case .date:
                    dateDays += sign * value
                    dates += sign
                    usedDates = true
                }
            }
            if usedDates {
                guard !usedClocks else { throw Failure.dateAndClock }
                guard seconds % day == 0 else { throw Failure.partialDays }
                let days = dateDays + seconds / day
                switch dates {
                case 0: return .success(daysAnswer(days))
                case 1: return .success(dateAnswer(days))
                default: throw Failure.twoDates
                }
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
                let (value, kind) = try parse(part, allowOverflow: allowOverflow)
                if kind == .clock { throw Failure.clockNotLength }
                if kind == .date { throw Failure.dateNotLength }
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

    private enum Kind { case length, clock, date }

    /// One part: seconds for a length or clock time, or a day number for a date.
    private static func parse(_ part: String, allowOverflow: Bool = false,
                              today: Int = dayNumber(of: Date())) throws -> (Int, Kind) {
        let compact = part.lowercased().filter { !$0.isWhitespace }

        if let date = try date(compact, part: part, today: today) { return (date, .date) }

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
                return (((hour % 12) + (isPM ? 12 : 0)) * 3600 + minute * 60, .clock)
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
            return (values[0] * 3600 + values[1] * 60 + (values.count == 3 ? values[2] : 0), .length)
        }

        // A plain number is minutes.
        if let minutes = Double(compact) { return (Int((minutes * 60).rounded()), .length) }

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
        return (Int(total.rounded()), .length)
    }

    private static let unitScale: [String: Double] = {
        var scales: [String: Double] = [:]
        for word in ["h", "hr", "hrs", "hour", "hours"] { scales[word] = 3600 }
        for word in ["m", "min", "mins", "minute", "minutes"] { scales[word] = 60 }
        for word in ["s", "sec", "secs", "second", "seconds"] { scales[word] = 1 }
        for word in ["d", "day", "days"] { scales[word] = Double(day) }
        for word in ["w", "wk", "wks", "week", "weeks"] { scales[word] = Double(7 * day) }
        return scales
    }()

    // MARK: Dates

    /// Dates are counted in whole days since 2001-01-01, worked out in UTC so there's no daylight saving.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// The day number of `date` as it reads on this Mac's calendar.
    private static func dayNumber(of date: Date) -> Int {
        let ymd = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return dayNumber(year: ymd.year!, month: ymd.month!, day: ymd.day!)!
    }

    /// Nil if there's no such day, like Feb 30.
    private static func dayNumber(year: Int, month: Int, day: Int) -> Int? {
        guard (1...12).contains(month), (1...31).contains(day),
              let date = utc.date(from: DateComponents(year: year, month: month, day: day)),
              utc.component(.day, from: date) == day
        else { return nil }
        return Int((date.timeIntervalSinceReferenceDate / Double(Self.day)).rounded(.down))
    }

    private static func date(ofDay dayNumber: Int) -> Date {
        Date(timeIntervalSinceReferenceDate: Double(dayNumber * day))
    }

    private static let weekdays: [String: Int] = { // Calendar weekday numbers, Sunday is 1
        var names: [String: Int] = [:]
        for (number, words) in [(1, ["sun", "sunday"]), (2, ["mon", "monday"]), (3, ["tue", "tues", "tuesday"]),
                                (4, ["wed", "weds", "wednesday"]), (5, ["thu", "thur", "thurs", "thursday"]),
                                (6, ["fri", "friday"]), (7, ["sat", "saturday"])] {
            for word in words { names[word] = number }
        }
        return names
    }()

    private static let months: [String: Int] = {
        var names: [String: Int] = [:]
        let full = ["january", "february", "march", "april", "may", "june", "july",
                    "august", "september", "october", "november", "december"]
        for (index, name) in full.enumerated() {
            names[name] = index + 1
            names[String(name.prefix(3))] = index + 1
        }
        names["sept"] = 9
        return names
    }()

    /// A date's day number, or nil if `compact` isn't trying to be a date.
    private static func date(_ compact: String, part: String, today: Int) throws -> Int? {
        switch compact {
        case "today": return today
        case "tomorrow", "tmrw": return today + 1
        case "yesterday": return today - 1
        default: break
        }

        // "fri": the coming Friday, or today if it's Friday.
        if let weekday = weekdays[compact] {
            let todayWeekday = utc.component(.weekday, from: date(ofDay: today))
            return today + (weekday - todayWeekday + 7) % 7
        }

        var month: Int, dayOfMonth: Int, year: Int?
        let letters = compact.prefix { $0.isLetter }
        if !letters.isEmpty {
            // "dec25", "december25", "dec25,2027" or "dec252027" (spaces are already gone)
            guard let m = months[String(letters)] else { return nil }
            let digits = compact.dropFirst(letters.count).filter { $0 != "," }
            guard digits.allSatisfy(\.isNumber), (1...6).contains(digits.count), digits.count != 3, digits.count != 4
            else { throw Failure.badDate(part) }
            month = m
            dayOfMonth = Int(digits.prefix(digits.count > 2 ? digits.count - 4 : digits.count))!
            year = digits.count > 2 ? Int(digits.suffix(4)) : nil
        } else if compact.contains("/") {
            // "12/25", "12/25/27" or "12/25/2027"
            let pieces = compact.split(separator: "/", omittingEmptySubsequences: false).map { Int($0) }
            guard (2...3).contains(pieces.count), pieces.allSatisfy({ $0 != nil }) else { throw Failure.badDate(part) }
            month = pieces[0]!
            dayOfMonth = pieces[1]!
            if pieces.count == 3 {
                let y = pieces[2]!
                year = y < 100 ? 2000 + y : y
            }
        } else {
            return nil
        }

        if let year {
            guard let date = dayNumber(year: year, month: month, day: dayOfMonth) else { throw Failure.badDate(part) }
            return date
        }
        // No year: the nearest one, looking a year either way.
        let thisYear = utc.component(.year, from: date(ofDay: today))
        let candidates = (thisYear - 1...thisYear + 1).compactMap { dayNumber(year: $0, month: month, day: dayOfMonth) }
        guard let nearest = candidates.min(by: { abs($0 - today) < abs($1 - today) }) else { throw Failure.badDate(part) }
        return nearest
    }

    /// "Wed, Jan 7, 2027", typed back in as "1/7/2027".
    private static func dateAnswer(_ dayNumber: Int) -> Answer {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utc.timeZone
        formatter.dateFormat = "EEE, MMM d, yyyy"
        let text = formatter.string(from: date(ofDay: dayNumber))
        formatter.dateFormat = "M/d/yyyy"
        return Answer(text: text, reuse: formatter.string(from: date(ofDay: dayNumber)))
    }

    /// "1 day", "77 days (11 weeks)" or "80 days (11w 3d)", typed back in as "80d".
    private static func daysAnswer(_ days: Int) -> Answer {
        let count = abs(days)
        var text = count == 1 ? "\(days) day" : "\(days) days"
        if count >= 7 {
            let (weeks, extra) = (count / 7, count % 7)
            text += extra == 0
                ? (weeks == 1 ? " (1 week)" : " (\(weeks) weeks)")
                : " (\(weeks)w \(extra)d)"
        }
        return Answer(text: text, reuse: "\(days)d")
    }

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
