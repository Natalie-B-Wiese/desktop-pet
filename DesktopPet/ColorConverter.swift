import Foundation

/// A color as red, green and blue from 0 to 1. Every color unit reads into this and shows from it.
struct RGBColor: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    /// Hue in degrees (0..<360). Greys have no real hue, so they get 0.
    private var hue: Double {
        let high = max(red, green, blue), delta = high - min(red, green, blue)
        guard delta > 0 else { return 0 }
        let sixths: Double = switch high {
        case red: (green - blue) / delta
        case green: (blue - red) / delta + 2
        default: (red - green) / delta + 4
        }
        let degrees = sixths * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    /// Hue in degrees, saturation and lightness from 0 to 1.
    var hsl: [Double] {
        let high = max(red, green, blue), low = min(red, green, blue)
        let lightness = (high + low) / 2
        let saturation = high == low ? 0 : (high - low) / (1 - abs(2 * lightness - 1))
        return [hue, saturation, lightness]
    }

    /// Hue in degrees, saturation and value (brightness) from 0 to 1.
    var hsv: [Double] {
        let high = max(red, green, blue), low = min(red, green, blue)
        return [hue, high == 0 ? 0 : (high - low) / high, high]
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        self.init(hue: hue, chroma: chroma, plus: lightness - chroma / 2)
    }

    init(hue: Double, saturation: Double, value: Double) {
        let chroma = value * saturation
        self.init(hue: hue, chroma: chroma, plus: value - chroma)
    }

    /// The shared last step of HSL and HSV: place the chroma around the color wheel, then lift every channel by `plus`.
    private init(hue: Double, chroma: Double, plus m: Double) {
        let h = hue.truncatingRemainder(dividingBy: 360) / 60
        let x = chroma * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch h {
        case ..<1: (chroma, x, 0)
        case ..<2: (x, chroma, 0)
        case ..<3: (0, chroma, x)
        case ..<4: (0, x, chroma)
        case ..<5: (x, 0, chroma)
        default: (chroma, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m)
    }
}

/// A way of writing a color in the Convert tab's Color category, like hex or hsl.
/// Each unit reads typed text into its own numbers (like [32, 100, 50] for hsl), which turn into an `RGBColor`.
struct ColorUnit: Identifiable {
    let symbol: String
    let name: String
    /// Shown in the empty box, so the order and range are clear before typing.
    let placeholder: String
    /// Shown under the box while it's empty or can't be read, like "R · G · B, 0–255".
    let hint: String
    /// Reads typed text into this unit's numbers, or says what's wrong.
    let read: (String) -> Result<[Double], ConvertUnit.Failure>
    let toRGB: ([Double]) -> RGBColor
    let fromRGB: (RGBColor) -> [Double]
    /// The answer, like "255, 136, 0" or "#FF8800".
    let show: ([Double]) -> String
    /// How the typed numbers were read, like "H 32° · S 100% · L 50%".
    let breakdown: ([Double]) -> String

    var id: String { symbol }

    typealias Failure = ConvertUnit.Failure

    static let all: [ColorUnit] = [
        hex,
        channels("rgb", "red, green, blue (0–255)", family: "rgb", placeholder: "255, 136, 0", hint: "R · G · B, 0–255",
                 [Channel("R", max: 255), Channel("G", max: 255), Channel("B", max: 255)],
                 toRGB: { RGBColor(red: $0[0] / 255, green: $0[1] / 255, blue: $0[2] / 255) },
                 fromRGB: { [$0.red * 255, $0.green * 255, $0.blue * 255] }),
        channels("rgb 0–1", "red, green, blue (0–1)", family: "rgb", placeholder: "1, 0.53, 0", hint: "R · G · B, 0–1",
                 [Channel("R", max: 1), Channel("G", max: 1), Channel("B", max: 1)],
                 toRGB: { RGBColor(red: $0[0], green: $0[1], blue: $0[2]) },
                 fromRGB: { [$0.red, $0.green, $0.blue] }),
        channels("hsl", "hue, saturation, lightness", family: "hsl", placeholder: "32, 100, 50", hint: "H 0–360 · S, L 0–100",
                 [Channel("H", max: 360, suffix: "°", wraps: true), Channel("S", max: 100, suffix: "%"), Channel("L", max: 100, suffix: "%")],
                 toRGB: { RGBColor(hue: $0[0], saturation: $0[1] / 100, lightness: $0[2] / 100) },
                 fromRGB: { let hsl = $0.hsl; return [hsl[0], hsl[1] * 100, hsl[2] * 100] }),
        channels("hsl 0–1", "hue, saturation, lightness (0–1)", family: "hsl", placeholder: "0.09, 1, 0.5", hint: "H · S · L, 0–1",
                 [Channel("H", max: 1, wraps: true), Channel("S", max: 1), Channel("L", max: 1)],
                 toRGB: { RGBColor(hue: $0[0] * 360, saturation: $0[1], lightness: $0[2]) },
                 fromRGB: { let hsl = $0.hsl; return [hsl[0] / 360, hsl[1], hsl[2]] }),
        channels("hsv", "hue, saturation, value", family: "hsv", placeholder: "32, 100, 100", hint: "H 0–360 · S, V 0–100",
                 [Channel("H", max: 360, suffix: "°", wraps: true), Channel("S", max: 100, suffix: "%"), Channel("V", max: 100, suffix: "%")],
                 toRGB: { RGBColor(hue: $0[0], saturation: $0[1] / 100, value: $0[2] / 100) },
                 fromRGB: { let hsv = $0.hsv; return [hsv[0], hsv[1] * 100, hsv[2] * 100] }),
        channels("hsv 0–1", "hue, saturation, value (0–1)", family: "hsv", placeholder: "0.09, 1, 1", hint: "H · S · V, 0–1",
                 [Channel("H", max: 1, wraps: true), Channel("S", max: 1), Channel("V", max: 1)],
                 toRGB: { RGBColor(hue: $0[0] * 360, saturation: $0[1], value: $0[2]) },
                 fromRGB: { let hsv = $0.hsv; return [hsv[0] / 360, hsv[1], hsv[2]] }),
    ]

    static func named(_ symbol: String?) -> ColorUnit? {
        all.first { $0.symbol == symbol }
    }

    // MARK: - Hex

    /// "#FF8800". Reads 3 or 6 digits in any case, with or without the "#". Its numbers are red, green and blue from 0 to 255.
    private static let hex = ColorUnit(
        symbol: "hex", name: "hex code", placeholder: "#FF8800", hint: "#RGB or #RRGGBB",
        read: { text in
            var digits = text.trimmingCharacters(in: .whitespaces)
            if digits.hasPrefix("#") { digits.removeFirst() }
            guard digits.allSatisfy(\.isHexDigit) else { return .failure(Failure(message: "Hex digits are 0–9 and A–F")) }
            switch digits.count {
            case 3: digits = digits.map { "\($0)\($0)" }.joined() // "f80" is "ff8800"
            case 6: break
            case 4, 8: return .failure(alphaFailure)
            default: return .failure(Failure(message: "Hex needs 3 or 6 digits"))
            }
            let value = Int(digits, radix: 16)!
            return .success([Double(value >> 16 & 0xFF), Double(value >> 8 & 0xFF), Double(value & 0xFF)])
        },
        toRGB: { RGBColor(red: $0[0] / 255, green: $0[1] / 255, blue: $0[2] / 255) },
        fromRGB: { [$0.red * 255, $0.green * 255, $0.blue * 255] },
        show: { numbers in "#" + numbers.map { String(format: "%02X", Int(rounded($0, to: 0))) }.joined() },
        breakdown: { "R \(Int($0[0])) · G \(Int($0[1])) · B \(Int($0[2]))" }
    )

    // MARK: - Three numbers

    /// One of a color's three numbers, like hsl's S. 0–255 and degree channels show whole numbers,
    /// percents 1 decimal place, and 0–1 channels 3.
    private struct Channel {
        let label: String
        let max: Double
        var suffix = ""
        /// Hue goes around a circle, so its top (360°, or 1) is the same as 0.
        var wraps = false

        init(_ label: String, max: Double, suffix: String = "", wraps: Bool = false) {
            self.label = label
            self.max = max
            self.suffix = suffix
            self.wraps = wraps
        }

        var decimals: Int { suffix == "%" ? 1 : max == 1 ? 3 : 0 }

        func text(_ value: Double) -> String {
            var value = ColorUnit.rounded(value, to: decimals)
            if wraps && value >= max { value = 0 }
            return MathEvaluator.format(value, maxFractionDigits: decimals)
        }
    }

    /// The color families a typed wrapper like "rgb(…)" can name, so typing an hsl color into rgb is caught.
    private static let wrapperFamilies = ["rgb": "rgb", "rgba": "rgb", "hsl": "hsl", "hsla": "hsl", "hsv": "hsv", "hsva": "hsv", "hsb": "hsv"]

    /// A unit typed as three numbers, like "32, 100, 50". Commas and spaces both separate them,
    /// "°" and "%" are ignored, and a wrapper like "hsl(…)" is fine if it's this unit's family.
    private static func channels(
        _ symbol: String, _ name: String, family: String, placeholder: String, hint: String, _ channels: [Channel],
        toRGB: @escaping ([Double]) -> RGBColor, fromRGB: @escaping (RGBColor) -> [Double]
    ) -> ColorUnit {
        ColorUnit(
            symbol: symbol, name: name, placeholder: placeholder, hint: hint,
            read: { text in
                var text = text.trimmingCharacters(in: .whitespaces).lowercased()
                if text.hasPrefix("#") { return .failure(Failure(message: "Looks like a hex color. Pick hex.")) }
                let wrapper = String(text.prefix { $0.isLetter })
                if !wrapper.isEmpty {
                    guard let wrapperFamily = wrapperFamilies[wrapper] else {
                        return .failure(Failure(message: "I don't understand \"\(wrapper)\""))
                    }
                    guard wrapperFamily == family else {
                        return .failure(Failure(message: "Looks like an \(wrapperFamily) color. Pick \(wrapperFamily)."))
                    }
                    text.removeFirst(wrapper.count)
                }
                let parts = text
                    .filter { !"()°%".contains($0) }
                    .split { $0 == "," || $0 == "/" || $0.isWhitespace }
                var numbers: [Double] = []
                for part in parts {
                    guard let number = Double(part.replacingOccurrences(of: "−", with: "-")) else {
                        return .failure(Failure(message: "I don't understand \"\(part)\""))
                    }
                    numbers.append(number)
                }
                if numbers.count == 4 { return .failure(alphaFailure) }
                guard numbers.count == 3 else { return .failure(Failure(message: "Needs 3 numbers, like \(placeholder)")) }
                for (number, channel) in zip(numbers, channels) where !(0...channel.max).contains(number) {
                    return .failure(Failure(message: "\(channel.label) must be 0–\(MathEvaluator.format(channel.max))"))
                }
                return .success(numbers)
            },
            toRGB: toRGB,
            fromRGB: fromRGB,
            show: { numbers in zip(numbers, channels).map { $1.text($0) }.joined(separator: ", ") },
            breakdown: { numbers in
                zip(numbers, channels).map { "\($1.label) \($1.text($0))\($1.suffix)" }.joined(separator: " · ")
            }
        )
    }

    // TODO: Alpha. Programs disagree on its range (0–1, 0–255 or a percent), so it's left out for now (see CLAUDE.md).
    private static let alphaFailure = Failure(message: "Alpha isn't supported yet")

    /// Rounds halves up, like people do (NumberFormatter would round 0.5 to the even 0).
    private static func rounded(_ value: Double, to decimals: Int) -> Double {
        let scale = pow(10, Double(decimals))
        return (value * scale).rounded() / scale
    }
}
