import AppKit
import Observation

/// The three replaceable colors in the pet image.
/// Pure red, green and blue pixels in the image are swapped for these; everything else is left alone.
struct PetPalette: Equatable {
    var main: NSColor      // pure red: body
    var secondary: NSColor // pure green: inner ears, muzzle, paws, tail tip (the van's first eye)
    var detail: NSColor    // pure blue: eyes (the van's second eye)
}

@Observable
final class PetSettings {
    /// Which cat pattern is showing.
    var character: PetCharacter {
        didSet {
            guard character != oldValue else { return }
            defaults.set(character.id, forKey: "character")
            onChange?()
        }
    }

    /// Every part's color, by `PetCharacter.partKeys`, so characters that share a part share its color.
    private var colors: [String: NSColor]

    /// The current character's three colors.
    var palette: PetPalette {
        get { palette(for: character.partKeys) }
        set {
            let old = palette
            guard newValue != old else { return }
            for (key, color) in zip(character.partKeys, [newValue.main, newValue.secondary, newValue.detail]) {
                colors[key] = color
                defaults.set(color.hexString, forKey: "color.\(key)")
            }
            onChange?()
        }
    }

    /// Whether the current character's colors are all their defaults.
    var isDefaultPalette: Bool {
        palette == palette(for: character.partKeys, from: Self.defaultColors)
    }

    /// Default colors for each part key.
    private static let defaultColors: [String: String] = [
        "main": "E8893A",
        "secondary": "F6E3C4",
        "detail": "4CAF50",
        "eye1": "3A7BD5",
        "eye2": "4CAF50",
    ]

    /// How many points each image pixel is drawn as. Whole numbers keep the pixel art crisp.
    /// Callers keep it within `scaleRange`; don't reassign it in `didSet` (with @Observable that recurses forever).
    var scale: Int {
        didSet {
            guard scale != oldValue else { return }
            defaults.set(scale, forKey: "scale")
            onScaleChange?()
        }
    }

    /// The pet's name exactly as typed (may be empty). Use `displayName` to show it.
    var name: String {
        didSet { if name != oldValue { defaults.set(name, forKey: "name") } }
    }

    static let maxNameLength = 20

    /// The name trimmed for display, or nil when the pet hasn't been named.
    var displayName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static let scaleRange = 2...12
    static let defaultScale = 6

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored var onScaleChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    init() {
        let stored = UserDefaults.standard
        character = PetCharacter.withID(stored.string(forKey: "character")) ?? .tuxedo
        colors = Self.defaultColors.reduce(into: [:]) { result, entry in
            result[entry.key] = Self.load("color.\(entry.key)", defaults: stored) ?? NSColor(hex: entry.value)!
        }
        let savedScale = stored.integer(forKey: "scale") // 0 when never saved
        scale = Self.scaleRange.contains(savedScale) ? savedScale : Self.defaultScale
        name = stored.string(forKey: "name") ?? ""
    }

    /// Resets the current character's colors. Parts it shares with other characters reset for them too.
    func reset() {
        palette = palette(for: character.partKeys, from: Self.defaultColors)
    }

    /// Switches to the next (+1) or previous (-1) character, wrapping around at either end.
    func cycleCharacter(by step: Int) {
        let all = PetCharacter.all
        let index = all.firstIndex(of: character) ?? 0
        character = all[((index + step) % all.count + all.count) % all.count]
    }

    private func palette(for keys: [String]) -> PetPalette {
        let fallback = palette(for: keys, from: Self.defaultColors)
        return PetPalette(
            main: colors[keys[0]] ?? fallback.main,
            secondary: colors[keys[1]] ?? fallback.secondary,
            detail: colors[keys[2]] ?? fallback.detail
        )
    }

    private func palette(for keys: [String], from hexes: [String: String]) -> PetPalette {
        let color = { NSColor(hex: hexes[keys[$0]] ?? "") ?? .gray }
        return PetPalette(main: color(0), secondary: color(1), detail: color(2))
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
