import AppKit
import Observation

/// Colors picked from the screen, as hex codes, newest first, saved across launches.
@Observable
final class ColorPicks {
    private(set) var hexes: [String] = []
    /// The color whose hex was just copied, to show "Copied!" on it for a moment.
    private(set) var justCopied: String?

    static let limit = 5
    private static let storageKey = "colorPicks"

    @ObservationIgnored private var sampler: NSColorSampler?

    init() {
        hexes = UserDefaults.standard.stringArray(forKey: Self.storageKey) ?? []
    }

    /// Shows macOS's magnifier to pick a color from anywhere on screen. A picked color goes to the top
    /// and its hex is copied. `done` runs afterwards, whether a color was picked or Esc cancelled.
    func pickFromScreen(done: @escaping () -> Void) {
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            guard let self else { return }
            self.sampler = nil
            if let color {
                add(color.hexString)
                copy(color.hexString)
            }
            done()
        }
    }

    /// Copies "#RRGGBB", ready to paste.
    func copy(_ hex: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("#\(hex)", forType: .string)
        justCopied = hex
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            if self?.justCopied == hex { self?.justCopied = nil }
        }
    }

    func delete(_ hex: String) {
        hexes.removeAll { $0 == hex }
        save()
    }

    func clear() {
        hexes = []
        save()
    }

    /// Picking a color that's already listed moves it back to the top.
    private func add(_ hex: String) {
        hexes.removeAll { $0 == hex }
        hexes.insert(hex, at: 0)
        hexes = Array(hexes.prefix(Self.limit))
        save()
    }

    private func save() {
        UserDefaults.standard.set(hexes, forKey: Self.storageKey)
    }
}
