import AppKit
import SwiftUI

/// A family of related colors, light to dark.
struct ColorFamily: Identifiable {
    let name: String
    let shades: [String] // hex, lightest first

    var id: String { name }
    /// The swatch that stands for the whole family in the family row.
    var representative: String { shades[3] }

    static let all: [ColorFamily] = [
        ColorFamily(name: "Red", shades: ["FFD6D6", "F7A1A1", "EF6B6B", "D93A3A", "A82424", "6E1515"]),
        ColorFamily(name: "Orange", shades: ["FFE3C7", "FFC08A", "F5A45F", "E8893A", "B8561A", "7A3810"]),
        ColorFamily(name: "Yellow", shades: ["FFF6C7", "FCE88A", "F5D547", "E0B623", "B08812", "735808"]),
        ColorFamily(name: "Olive", shades: ["EEF0D2", "D6DC9E", "B8C26A", "98A33F", "6F7A2A", "474E1A"]),
        ColorFamily(name: "Green", shades: ["D9F2D0", "A8DE96", "72C45B", "4CAF50", "2F7A25", "1B4D16"]),
        ColorFamily(name: "Teal", shades: ["D0F2EE", "94DED5", "52C2B5", "23A094", "147369", "0B4A44"]),
        ColorFamily(name: "Blue", shades: ["D6E6FF", "A1C4F7", "6B9FEB", "3A7BD5", "2456A3", "14356B"]),
        ColorFamily(name: "Purple", shades: ["E8DDFA", "CBB5F2", "A98AE3", "8A63CF", "653FA6", "402470"]),
        // Most real cats and dogs are browns and neutrals, so they get families of their own.
        ColorFamily(name: "Brown", shades: ["F6E3C4", "E0C097", "C69A6B", "9E6E45", "7A4E2E", "4A2E1B"]),
        // The "lilac" or "minky" coat: a soft, sandy warm gray.
        ColorFamily(name: "Brown-gray", shades: ["EFEBE3", "DBD2C4", "BFB2A0", "9F917F", "7D6F60", "574C42"]),
        // The "blue" of Russian Blue, Chartreux and Korat cats.
        ColorFamily(name: "Blue-gray", shades: ["E3E8EE", "C3CCD6", "A0ACBA", "7E8C9C", "5C6878", "3A4452"]),
        ColorFamily(name: "Neutral", shades: ["FFFFFF", "D9D9D9", "ABABAB", "7A7A7A", "4A4A4A", "1E1E1E"]),
    ]

    static func containing(_ hex: String) -> ColorFamily? {
        all.first { $0.shades.contains(hex) }
    }
}

/// The bubble's Customize page. Pick a part, then a color family, then a shade.
/// Topsy herself is the preview.
struct BubbleCustomizePage: View {
    let settings: PetSettings

    /// Kept unfocused on open, so a stray keypress can't overwrite the name.
    @FocusState private var nameFocused: Bool
    /// Which part (0 red, 1 green, 2 blue) is being colored.
    @State private var selectedSlot: Int
    /// The family whose shades are showing.
    @State private var selectedFamily: String?

    /// Sizes offered as buttons: how many points each image pixel is drawn as.
    private static let sizes: [(scale: Int, title: String)] = [(4, "S"), (5, "M"), (6, "L")]
    private static let slotKeyPaths: [WritableKeyPath<PetPalette, NSColor>] = [\.main, \.secondary, \.detail]

    private var character: PetCharacter { settings.character }
    private var slots: [Int] {
        let used = PetRenderer.usedSlots(for: character)
        return character.partOrder.filter { used[$0] }
    }

    init(settings: PetSettings) {
        self.settings = settings
        let used = PetRenderer.usedSlots(for: settings.character)
        let first = settings.character.partOrder.first { used[$0] } ?? 0
        _selectedSlot = State(initialValue: first)
        _selectedFamily = State(initialValue: ColorFamily.containing(
            settings.palette[keyPath: Self.slotKeyPaths[first]].hexString
        )?.name)
    }

    private var currentHex: String {
        settings.palette[keyPath: Self.slotKeyPaths[selectedSlot]].hexString
    }

    var body: some View {
        VStack(spacing: 10) {
            // The name box and the size buttons are as wide as the color family box, edges lined up,
            // with their labels in the margin to the left.
            TextField("Name your pet", text: Binding(
                get: { settings.name },
                set: { settings.name = String($0.prefix(PetSettings.maxNameLength)) }
            ))
            .bubbleFieldStyle()
            .focused($nameFocused)
            .labeled("Name", width: Self.familyBoxWidth)

            BubbleTabs(
                selection: Binding(get: { settings.scale }, set: { settings.scale = $0 }),
                options: Self.sizes.map { ($0.scale, $0.title) }
            )
            .labeled("Size", width: Self.familyBoxWidth)

            characterPicker
            slotPicker
            familyRow
            shadeRow

            BubbleButton("Reset colors", systemImage: "arrow.counterclockwise", style: .quiet, centered: true) {
                settings.reset()
                selectedFamily = ColorFamily.containing(currentHex)?.name
            }
            .disabled(settings.isDefaultPalette)
            .opacity(settings.isDefaultPalette ? 0.4 : 1)
        }
        .onAppear {
            DispatchQueue.main.async { nameFocused = false }
        }
        .onChange(of: settings.character) {
            // Keep the same part selected if the new pattern has it, and show its color's family.
            if !slots.contains(selectedSlot) { selectedSlot = slots.first ?? 0 }
            selectedFamily = ColorFamily.containing(currentHex)?.name
        }
    }

    /// A boxed row as wide as the color family box: species arrows around its icon,
    /// then pattern arrows around "3/5". Both wrap around at the ends.
    private var characterPicker: some View {
        let patterns = character.species.characters
        let position = (patterns.firstIndex(of: character) ?? 0) + 1
        return HStack(spacing: 28) {
            stepper(help: "species", step: settings.cycleSpecies) {
                Image(nsImage: NSImage(named: character.species.iconName) ?? NSImage())
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 24)
            }
            stepper(help: "pattern", step: settings.cycleCharacter) {
                Text("\(position)/\(patterns.count)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 30)
            }
        }
        .padding(.vertical, 3)
        .frame(width: Self.familyBoxWidth)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.15), lineWidth: 1))
    }

    /// "‹ label ›", where the arrows call `step` with -1 or +1.
    private func stepper(help: String, step: @escaping (Int) -> Void, @ViewBuilder label: () -> some View) -> some View {
        HStack(spacing: 2) {
            HeaderIconButton(systemImage: "chevron.left", help: "Previous \(help)") { step(-1) }
            label()
            HeaderIconButton(systemImage: "chevron.right", help: "Next \(help)") { step(1) }
        }
    }

    /// The character's parts, each showing its current color. The selected one gets a ring.
    private var slotPicker: some View {
        HStack(spacing: 14) {
            ForEach(slots, id: \.self) { slot in
                let hex = settings.palette[keyPath: Self.slotKeyPaths[slot]].hexString
                Button {
                    selectedSlot = slot
                    selectedFamily = ColorFamily.containing(hex)?.name
                } label: {
                    VStack(spacing: 3) {
                        circle(hex, size: 26, selected: slot == selectedSlot)
                        Text(character.partNames[slot])
                            .font(.system(size: 10, weight: slot == selectedSlot ? .bold : .medium, design: .rounded))
                            .opacity(slot == selectedSlot ? 1 : 0.6)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private static let familiesPerRow = 6
    private static let familyCircleSize: CGFloat = 20
    private static let familySpacing: CGFloat = 6
    private static let familyBoxPadding: CGFloat = 8
    /// The color family box's full width, which the size buttons match.
    private static let familyBoxWidth = CGFloat(familiesPerRow) * (familyCircleSize + 6)
        + CGFloat(familiesPerRow - 1) * familySpacing + 2 * familyBoxPadding

    /// Two rows of six: bright colors on top, pet coat colors below.
    private var familyRow: some View {
        let perRow = Self.familiesPerRow
        return VStack(spacing: 2) {
            ForEach(0..<(ColorFamily.all.count + perRow - 1) / perRow, id: \.self) { row in
                HStack(spacing: Self.familySpacing) {
                    ForEach(ColorFamily.all[(row * perRow)..<min((row + 1) * perRow, ColorFamily.all.count)]) { family in
                        Button {
                            selectedFamily = family.name
                        } label: {
                            circle(family.representative, size: Self.familyCircleSize, selected: family.name == selectedFamily)
                        }
                        .buttonStyle(.plain)
                        .help(family.name)
                    }
                }
            }
        }
        // A light box sets the families apart from the shades below.
        .padding(.horizontal, Self.familyBoxPadding)
        .padding(.vertical, 5)
        .frame(width: Self.familyBoxWidth)
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.15), lineWidth: 1))
    }

    /// Shades of the chosen family.
    private var shadeRow: some View {
        HStack(spacing: 6) {
            if let family = ColorFamily.all.first(where: { $0.name == selectedFamily }) {
                ForEach(family.shades, id: \.self) { hex in
                    Button {
                        settings.palette[keyPath: Self.slotKeyPaths[selectedSlot]] = NSColor(hex: hex)!
                    } label: {
                        circle(hex, size: 24, selected: hex == currentHex)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Pick a color family")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.5)
                    .frame(height: 30)
            }

        }
    }

    private func circle(_ hex: String, size: CGFloat, selected: Bool) -> some View {
        Circle()
            .fill(Color(nsColor: NSColor(hex: hex) ?? .gray))
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
            .padding(2)
            .overlay(Circle().stroke(.black, lineWidth: selected ? 2 : 0))
            .frame(width: size + 6, height: size + 6)
            .contentShape(Circle())
    }
}

private extension View {
    /// Sets the control's width and puts a small label in the margin to its left.
    func labeled(_ label: String, width: CGFloat) -> some View {
        frame(width: width)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
    }
}
