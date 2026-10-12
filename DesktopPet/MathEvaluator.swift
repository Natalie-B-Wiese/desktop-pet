import Foundation

/// Evaluates typed arithmetic like "2^(3+1) * -1.5".
///
/// Supports + - * / ^, parentheses, decimals, unary minus, and implied multiplication
/// such as "2(3+4)", "(1+2)(3+4)" or "2sqrt(9)". Usual precedence: ^ (right to left) binds tightest,
/// then unary minus (so -2^2 is -4), then * and /, then + and -.
///
/// Also:
/// - `sqrt(9)` (or `√9`) and `abs(-4)`
/// - `ans` or `_` is the last answer, passed in as `ans`
/// - thousands separators: "1,250,000" (a comma must be followed by exactly three digits)
/// - percent: "15%" is 0.15, but adding or subtracting a percent works like a tip or a discount,
///   so "80 + 20%" is 96 and "80 - 25%" is 60
enum MathEvaluator {
    enum Failure: Error, Equatable {
        case empty
        case unexpected(Character)
        case unknownWord(String)
        case noPreviousAnswer
        case unexpectedEnd
        case missingCloseParen
        case divideByZero
        case notANumber

        var message: String {
            switch self {
            case .empty: "Type an equation first"
            case .unexpected(let c): "I don't understand \"\(c)\""
            case .unknownWord(let word): "I don't know \"\(word)\""
            case .noPreviousAnswer: "There's no answer yet"
            case .unexpectedEnd: "That seems unfinished"
            case .missingCloseParen: "Missing a \")\""
            case .divideByZero: "Can't divide by zero"
            case .notANumber: "That doesn't have a real answer"
            }
        }
    }

    static func evaluate(_ text: String, ans: Double? = nil) -> Result<Double, Failure> {
        var parser = Parser(text, ans: ans)
        do {
            guard !parser.atEnd else { throw Failure.empty }
            let value = try parser.expression()
            if let extra = parser.peek {
                throw Failure.unexpected(extra)
            }
            guard value.isFinite else { throw Failure.notANumber }
            return .success(value)
        } catch let failure as Failure {
            return .failure(failure)
        } catch {
            return .failure(.unexpectedEnd)
        }
    }

    /// "16", "0.3333333333", "1.5e+20": up to 10 decimal places, no trailing zeros.
    /// Rounds to at most `maxFractionDigits` decimal places. `grouping` adds thousands commas ("1,234.5").
    static func format(_ value: Double, maxFractionDigits: Int = 10, grouping: Bool = false) -> String {
        if value == 0 { return "0" } // also turns -0 into 0
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            return String(format: "%.6g", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.groupingSeparator = ","
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSNumber) ?? String(value)
    }

    private struct Parser {
        private let chars: [Character]
        private let ans: Double?
        private var index = 0

        init(_ text: String, ans: Double?) {
            // Accept the usual stand-ins for × ÷ and the true minus sign.
            chars = text.map { c in
                switch c {
                case "×", "·": "*"
                case "÷": "/"
                case "−", "–": "-"
                default: c
                }
            }.filter { !$0.isWhitespace }
            self.ans = ans
        }

        var atEnd: Bool { index >= chars.count }
        var peek: Character? { atEnd ? nil : chars[index] }

        private func peek(ahead offset: Int) -> Character? {
            index + offset < chars.count ? chars[index + offset] : nil
        }

        private mutating func take(_ c: Character) -> Bool {
            guard peek == c else { return false }
            index += 1
            return true
        }

        // expression := term (("+" | "-") term)*
        // A term that's just a percent ("+ 20%") is a percent of the value so far.
        mutating func expression() throws -> Double {
            var value = try term().value
            while true {
                if take("+") {
                    let next = try term()
                    value += next.isPercent ? value * next.value : next.value
                } else if take("-") {
                    let next = try term()
                    value -= next.isPercent ? value * next.value : next.value
                } else {
                    return value
                }
            }
        }

        // term := unary (("*" | "/") unary | implied multiplication)*
        private mutating func term() throws -> (value: Double, isPercent: Bool) {
            var (value, isPercent) = try unary()
            while true {
                if take("*") {
                    value *= try unary().value
                } else if take("/") {
                    let divisor = try unary().value
                    guard divisor != 0 else { throw Failure.divideByZero }
                    value /= divisor
                } else if let c = peek, c == "(" || c == "√" || c == "_" || c.isLetter {
                    value *= try unary().value // "2(3)", "(1+2)(3+4)", "2sqrt(9)"
                } else {
                    return (value, isPercent)
                }
                isPercent = false
            }
        }

        // unary := ("-" | "+") unary | power "%"?
        private mutating func unary() throws -> (value: Double, isPercent: Bool) {
            if take("-") {
                let (value, isPercent) = try unary()
                return (-value, isPercent)
            }
            if take("+") { return try unary() }
            let value = try power()
            return take("%") ? (value / 100, true) : (value, false)
        }

        // power := primary ("^" unary)?   — right to left, and allows 2^-1
        private mutating func power() throws -> Double {
            let base = try primary()
            guard take("^") else { return base }
            let exponent = try unary().value
            let result = pow(base, exponent)
            guard !result.isNaN else { throw Failure.notANumber }
            return result
        }

        // primary := number | "(" expression ")" | "ans" | "_" | ("sqrt" | "√" | "abs") primary
        private mutating func primary() throws -> Double {
            guard let c = peek else { throw Failure.unexpectedEnd }
            if take("(") {
                let value = try expression()
                guard take(")") else {
                    throw atEnd ? Failure.missingCloseParen : Failure.unexpected(peek!)
                }
                return value
            }
            if take("_") { return try lastAnswer() }
            if take("√") { return try squareRoot(primary()) }
            if c.isLetter { return try word() }
            guard Self.startsNumber(c) else { throw Failure.unexpected(c) }
            return try number()
        }

        /// Digits with an optional decimal point and thousands commas, like "1,250.5".
        private mutating func number() throws -> Double {
            var digits = ""
            var sawDot = false
            while let d = peek {
                if d.isNumber {
                    digits.append(d)
                } else if d == "." && !sawDot {
                    sawDot = true
                    digits.append(d)
                } else if d == "," && !sawDot && isThousandsComma() {
                    // skip it
                } else {
                    break
                }
                index += 1
            }
            guard let value = Double(digits) else { throw Failure.unexpected(".") }
            return value
        }

        /// A comma between digits with exactly three digits after it, as in "1,250".
        private func isThousandsComma() -> Bool {
            guard index > 0, chars[index - 1].isNumber else { return false }
            let after = (1...4).map { peek(ahead: $0) }
            return after[0...2].allSatisfy { $0?.isNumber == true } && after[3]?.isNumber != true
        }

        /// A name: "ans", or a function applied to what follows, as in "sqrt(9)" or "abs(-4)".
        private mutating func word() throws -> Double {
            var name = ""
            while let c = peek, c.isLetter {
                name.append(c)
                index += 1
            }
            switch name.lowercased() {
            case "ans": return try lastAnswer()
            case "sqrt": return try squareRoot(primary())
            case "abs": return abs(try primary())
            default: throw Failure.unknownWord(name)
            }
        }

        private func lastAnswer() throws -> Double {
            guard let ans else { throw Failure.noPreviousAnswer }
            return ans
        }

        private func squareRoot(_ value: Double) throws -> Double {
            guard value >= 0 else { throw Failure.notANumber }
            return value.squareRoot()
        }

        private static func startsNumber(_ c: Character) -> Bool {
            c.isNumber || c == "."
        }
    }
}
