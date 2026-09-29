import Foundation

/// Evaluates typed arithmetic like "2^(3+1) * -1.5".
///
/// Supports + - * / ^, parentheses, decimals, unary minus, and implied multiplication
/// such as "2(3+4)" or "(1+2)(3+4)". Usual precedence: ^ (right to left) binds tightest,
/// then unary minus (so -2^2 is -4), then * and /, then + and -.
enum MathEvaluator {
    enum Failure: Error, Equatable {
        case empty
        case unexpected(Character)
        case unexpectedEnd
        case missingCloseParen
        case divideByZero
        case notANumber

        var message: String {
            switch self {
            case .empty: "Type an equation first"
            case .unexpected(let c): "I don't understand \"\(c)\""
            case .unexpectedEnd: "That seems unfinished"
            case .missingCloseParen: "Missing a \")\""
            case .divideByZero: "Can't divide by zero"
            case .notANumber: "That doesn't have a real answer"
            }
        }
    }

    static func evaluate(_ text: String) -> Result<Double, Failure> {
        var parser = Parser(text)
        do {
            guard !parser.atEnd else { throw Failure.empty }
            let value = try parser.expression()
            if let extra = parser.peek {
                throw extra == ")" ? Failure.unexpected(")") : Failure.unexpected(extra)
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
    static func format(_ value: Double) -> String {
        if value == 0 { return "0" } // also turns -0 into 0
        let magnitude = abs(value)
        if magnitude >= 1e15 || magnitude < 1e-9 {
            return String(format: "%.6g", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 10
        formatter.decimalSeparator = "."
        return formatter.string(from: value as NSNumber) ?? String(value)
    }

    private struct Parser {
        private let chars: [Character]
        private var index = 0

        init(_ text: String) {
            // Accept the usual stand-ins for × ÷ and the true minus sign.
            chars = text.map { c in
                switch c {
                case "×", "·": "*"
                case "÷": "/"
                case "−", "–": "-"
                default: c
                }
            }.filter { !$0.isWhitespace }
        }

        var atEnd: Bool { index >= chars.count }
        var peek: Character? { atEnd ? nil : chars[index] }

        private mutating func take(_ c: Character) -> Bool {
            guard peek == c else { return false }
            index += 1
            return true
        }

        // expression := term (("+" | "-") term)*
        mutating func expression() throws -> Double {
            var value = try term()
            while true {
                if take("+") { value += try term() }
                else if take("-") { value -= try term() }
                else { return value }
            }
        }

        // term := unary (("*" | "/") unary | implied multiplication)*
        private mutating func term() throws -> Double {
            var value = try unary()
            while true {
                if take("*") {
                    value *= try unary()
                } else if take("/") {
                    let divisor = try unary()
                    guard divisor != 0 else { throw Failure.divideByZero }
                    value /= divisor
                } else if peek == "(" {
                    value *= try unary() // "2(3)" or "(1+2)(3+4)"
                } else {
                    return value
                }
            }
        }

        // unary := ("-" | "+") unary | power
        private mutating func unary() throws -> Double {
            if take("-") { return -(try unary()) }
            if take("+") { return try unary() }
            return try power()
        }

        // power := primary ("^" unary)?   — right to left, and allows 2^-1
        private mutating func power() throws -> Double {
            let base = try primary()
            guard take("^") else { return base }
            let exponent = try unary()
            let result = pow(base, exponent)
            guard !result.isNaN else { throw Failure.notANumber }
            return result
        }

        // primary := number | "(" expression ")"
        private mutating func primary() throws -> Double {
            guard let c = peek else { throw Failure.unexpectedEnd }
            if take("(") {
                let value = try expression()
                guard take(")") else {
                    throw atEnd ? Failure.missingCloseParen : Failure.unexpected(peek!)
                }
                return value
            }
            guard Self.startsNumber(c) else { throw Failure.unexpected(c) }
            let start = index
            var sawDot = false
            while let d = peek, d.isNumber || (d == "." && !sawDot) {
                if d == "." { sawDot = true }
                index += 1
            }
            guard let value = Double(String(chars[start..<index])) else {
                throw Failure.unexpected(".")
            }
            return value
        }

        private static func startsNumber(_ c: Character) -> Bool {
            c.isNumber || c == "."
        }
    }
}
