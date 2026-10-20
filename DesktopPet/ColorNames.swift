import AppKit

/// Everyday names for picked colors, so her chatter can say "coral" instead of "#FF7F50".
/// A short list on purpose (Natalie dropped niche names like periwinkle and forest green); a name can
/// have a few reference colors (light, mid, dark grey) so each covers its whole range.
enum ColorNames {
    private static let references: [(name: String, hex: String)] = [
        ("red", "E0201B"), ("red", "B71C1C"),
        ("maroon", "800020"), ("maroon", "5C1A1B"),
        ("coral", "FF7F50"),
        ("orange", "FF8C00"), ("orange", "E8893A"),
        ("peach", "FFCBA4"),
        ("gold", "D4A017"),
        ("yellow", "FFE135"), ("yellow", "F4D03F"),
        ("olive", "808000"), ("olive", "6B6B2A"),
        ("lime", "9ACD32"), ("lime", "B5E550"),
        ("green", "2E9E44"), ("green", "1B5E20"), ("green", "5DBB63"),
        ("mint", "98E5BE"),
        ("teal", "008080"), ("teal", "2A9D8F"), ("teal", "30C8C0"),
        ("sky blue", "87CEEB"), ("sky blue", "00BFFF"), ("sky blue", "00FFFF"),
        ("blue", "1E5BD8"), ("blue", "4A7BD0"), ("blue", "0000FF"), ("blue", "2040F0"),
        ("navy", "1B2A5A"),
        ("lavender", "B9A3E3"),
        ("purple", "7B2FBE"), ("purple", "4B1D6B"), ("purple", "9C6ADE"),
        ("pink", "F7A8C4"),
        ("hot pink", "FF3D9A"), ("hot pink", "FF00FF"),
        ("brown", "7B4A2A"), ("brown", "4A2C1A"), ("brown", "A0522D"),
        ("tan", "C8A27A"),
        ("beige", "E8DCC0"),
        ("white", "FFFFFF"),
        ("grey", "C4C4C4"), ("grey", "8C8C8C"), ("grey", "555555"),
        ("black", "141414"),
    ]

    private static let referenceLabs = references.map { (name: $0.name, lab: lab(hex: $0.hex)) }

    /// The everyday name closest to `color`, as people see color differences (CIE Lab).
    static func name(for color: NSColor) -> String {
        let target = lab(color)
        return referenceLabs.min { distance($0.lab, target) < distance($1.lab, target) }?.name ?? "that color"
    }

    /// Whether two colors are close enough to count as the same (Lab distance under 15: a few shades lighter,
    /// darker or tinted still count; Natalie found 8 too picky, missing a grey near Topsy's).
    static func looksAlike(_ a: NSColor, _ b: NSColor) -> Bool {
        distance(lab(a), lab(b)) < 15
    }

    private typealias Lab = (l: Double, a: Double, b: Double)

    private static func distance(_ x: Lab, _ y: Lab) -> Double {
        ((x.l - y.l) * (x.l - y.l) + (x.a - y.a) * (x.a - y.a) + (x.b - y.b) * (x.b - y.b)).squareRoot()
    }

    private static func lab(hex: String) -> Lab {
        let value = Int(hex, radix: 16) ?? 0
        return lab(red: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }

    private static func lab(_ color: NSColor) -> Lab {
        let c = color.usingColorSpace(.sRGB) ?? color
        return lab(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }

    /// sRGB (0–1) → CIE Lab, D65 white.
    private static func lab(red: Double, green: Double, blue: Double) -> Lab {
        func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        let fx = f(x), fy = f(y), fz = f(z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }
}
