import AppKit
import Observation

/// The three replaceable colors in the pet image.
/// Pure red, green and blue pixels in pet.png are swapped for these; everything else is left alone.
struct PetPalette: Equatable {
    var main: NSColor      // pure red: body
    var secondary: NSColor // pure green: inner ears, muzzle, paws, tail tip
    var detail: NSColor    // pure blue: eyes

    static let `default` = PetPalette(
        main: NSColor(hex: "E8893A")!,
        secondary: NSColor(hex: "F6E3C4")!,
        detail: NSColor(hex: "4CAF50")!
    )
}

@Observable
final class PetSettings {
    var palette: PetPalette {
        didSet {
            guard palette != oldValue else { return }
            save()
            onChange?()
        }
    }

    /// How many points each image pixel is drawn as. Whole numbers keep the pixel art crisp.
    /// Callers keep it within `scaleRange`; don't reassign it in `didSet` (with @Observable that recurses forever).
    var scale: Int {
        didSet {
            guard scale != oldValue else { return }
            defaults.set(scale, forKey: "scale")
            onScaleChange?()
        }
    }

    static let scaleRange = 2...12
    static let defaultScale = 6

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onScaleChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    init() {
        let fallback = PetPalette.default
        palette = PetPalette(
            main: Self.load("color.main", defaults: .standard) ?? fallback.main,
            secondary: Self.load("color.secondary", defaults: .standard) ?? fallback.secondary,
            detail: Self.load("color.detail", defaults: .standard) ?? fallback.detail
        )
        let savedScale = UserDefaults.standard.integer(forKey: "scale") // 0 when never saved
        scale = Self.scaleRange.contains(savedScale) ? savedScale : Self.defaultScale
    }

    func reset() {
        palette = .default
    }

    private func save() {
        defaults.set(palette.main.hexString, forKey: "color.main")
        defaults.set(palette.secondary.hexString, forKey: "color.secondary")
        defaults.set(palette.detail.hexString, forKey: "color.detail")
    }

    private static func load(_ key: String, defaults: UserDefaults) -> NSColor? {
        defaults.string(forKey: key).flatMap(NSColor.init(hex:))
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else { return nil }
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(
            format: "%02X%02X%02X",
            Int((c.redComponent * 255).rounded()),
            Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded())
        )
    }
}
