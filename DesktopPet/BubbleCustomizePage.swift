import AppKit
import SwiftUI

/// The bubble's Customize page: name, colors (as swatches) and size. Topsy herself is the preview.
struct BubbleCustomizePage: View {
    let settings: PetSettings

    /// Kept unfocused on open, so a stray keypress can't overwrite the name.
    @FocusState private var nameFocused: Bool

    /// Sizes offered as buttons: how many points each image pixel is drawn as.
    private static let sizes: [(scale: Int, title: String)] = [(4, "S"), (5, "M"), (6, "L"), (8, "XL")]

    private static let bodySwatches = ["E8893A", "7A7574", "2B2B2B", "F2F0EB", "8B5A3C", "E9D2A6", "BA94E0"]
    private static let accentSwatches = ["F6E3C4", "FFFFFF", "D0D0D0", "F2B8C6", "D9B38C", "555555", "D6F4E4"]
    private static let eyeSwatches = ["4CAF50", "3A7BD5", "E0A526", "B8612B", "8E8C3A", "9B7BD8", "202020"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Name your pet", text: Binding(
                get: { settings.name },
                set: { settings.name = String($0.prefix(PetSettings.maxNameLength)) }
            ))
            .bubbleFieldStyle()
            .focused($nameFocused)

            colorRow("Body", \.main, swatches: Self.bodySwatches)
            colorRow("Accents", \.secondary, swatches: Self.accentSwatches)
            colorRow("Eyes", \.detail, swatches: Self.eyeSwatches)

            HStack(spacing: 6) {
                Text("Size")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .frame(width: Self.labelWidth, alignment: .leading)
                BubbleTabs(
                    selection: Binding(get: { settings.scale }, set: { settings.scale = $0 }),
                    options: Self.sizes.map { ($0.scale, $0.title) }
                )
            }

            BubbleButton("Reset colors", systemImage: "arrow.counterclockwise", style: .quiet, centered: true) {
                settings.reset()
            }
            .disabled(settings.palette == .default)
            .opacity(settings.palette == .default ? 0.4 : 1)
        }
        .onAppear {
            DispatchQueue.main.async { nameFocused = false }
        }
    }

    private static let labelWidth: CGFloat = 52

    private func colorRow(_ title: String, _ part: WritableKeyPath<PetPalette, NSColor>, swatches: [String]) -> some View {
        let current = settings.palette[keyPath: part].hexString
        let isCustom = !swatches.contains(current)
        return HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: Self.labelWidth, alignment: .leading)
            ForEach(swatches, id: \.self) { hex in
                Button {
                    settings.palette[keyPath: part] = NSColor(hex: hex)!
                } label: {
                    swatch(Color(nsColor: NSColor(hex: hex)!), selected: hex == current)
                }
                .buttonStyle(.plain)
            }
            // "More…": the full macOS color picker; shows the color when it isn't a swatch.
            Button {
                ColorPanelBridge.shared.open(with: settings.palette[keyPath: part]) { color in
                    settings.palette[keyPath: part] = color
                }
            } label: {
                ZStack {
                    if isCustom {
                        swatch(Color(nsColor: settings.palette[keyPath: part]), selected: true)
                    } else {
                        Circle()
                            .fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
                    }
                }
                .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help("More colors…")
        }
    }

    private func swatch(_ color: Color, selected: Bool) -> some View {
        Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
            .padding(2)
            .overlay(Circle().stroke(.black, lineWidth: selected ? 2 : 0))
            .frame(width: 22, height: 22)
            .contentShape(Circle())
    }
}

/// Opens the shared macOS color panel and reports picks back, for the "More…" swatch.
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()
    private var onChange: ((NSColor) -> Void)?

    func open(with color: NSColor, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        self.onChange = nil // don't echo the starting color back
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        self.onChange = onChange
        NSApp.activate()
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        onChange?(panel.color.usingColorSpace(.sRGB) ?? panel.color)
    }
}
