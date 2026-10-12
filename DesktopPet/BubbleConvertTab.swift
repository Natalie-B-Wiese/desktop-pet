import AppKit
import SwiftUI

/// The Math page's Convert tab: type an amount, pick two units, and see the answer as you type.
/// The amount can be math too, like "5+2" (or "1:09" for the Time category's h:mm). Click the answer to copy it.
/// The Color category takes a color instead, like "#FF8800" or "32, 100, 50", with a line showing how it was read and a swatch.
/// The Range category has min – max boxes in place of the unit menus, and maps the number from one range onto the other.
struct BubbleConvertTab: View {
    var onClose: () -> Void

    @AppStorage("convert.category") private var categoryName = ConvertCategory.all[0].name
    @State private var input = ""
    @State private var fromSymbol = ""
    @State private var toSymbol = ""
    @State private var justCopied = false
    // The Range category's two ranges, kept as typed (they can be math too).
    @AppStorage("convert.Range.fromMin") private var rangeFromMin = "0"
    @AppStorage("convert.Range.fromMax") private var rangeFromMax = "1"
    @AppStorage("convert.Range.toMin") private var rangeToMin = "0"
    @AppStorage("convert.Range.toMax") private var rangeToMax = "100"
    @FocusState private var inputFocused: Bool

    private static let unitMenuWidth: CGFloat = 74
    private static let rangeEndWidth: CGFloat = 46

    private var category: ConvertCategory {
        ConvertCategory.named(categoryName) ?? ConvertCategory.all[0]
    }
    // The chosen units' symbols, falling back to the defaults if a saved one is gone.
    private var from: String { category.has(fromSymbol) ? fromSymbol : category.defaultFrom }
    private var to: String { category.has(toSymbol) ? toSymbol : category.defaultTo }

    /// The converted amount (or an error message), nil while the box is empty.
    private var conversion: Conversion? {
        let text = input.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if category.isRange {
            return ConvertCategory.mapRange(text, from: (rangeFromMin, rangeFromMax), to: (rangeToMin, rangeToMax))
        }
        return category.convert(text, from: from, to: to)
    }
    private var result: Result<String, ConvertUnit.Failure>? { conversion?.answer }

    private var fromColorUnit: ColorUnit? { category.isColor ? ColorUnit.named(from) : nil }

    var body: some View {
        VStack(spacing: 6) {
            BubblePopUp(title: category.name) {
                ForEach(ConvertCategory.all) { option in
                    Button(option.name) { categoryName = option.name }
                }
            }

            HStack(spacing: 4) {
                TextField(fromColorUnit?.placeholder ?? (category.isRange ? "Number" : "Amount"), text: $input)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
                    .focused($inputFocused)
                    .onExitCommand(perform: onClose) // Esc closes the menu
                if category.isRange {
                    rangeBoxes(min: $rangeFromMin, max: $rangeFromMax)
                } else {
                    unitMenu(selection: from) { fromSymbol = $0 }
                }
            }

            if let fromColorUnit {
                // How the color was read with a swatch, or which numbers to type while it can't be read yet.
                HStack(spacing: 5) {
                    if let color = conversion?.color {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(.sRGB, red: color.red, green: color.green, blue: color.blue))
                            .frame(width: 12, height: 12)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.3), lineWidth: 1))
                    }
                    Text(conversion?.breakdown ?? fromColorUnit.hint)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .opacity(conversion?.breakdown == nil ? 0.4 : 0.6)
                }
                .frame(maxWidth: .infinity, minHeight: 12, alignment: .leading) // the same height with or without the swatch
                .padding(.horizontal, 8)
            }

            HeaderIconButton(systemImage: "arrow.up.arrow.down", help: category.isRange ? "Swap ranges" : "Swap units") {
                if category.isRange {
                    (rangeFromMin, rangeFromMax, rangeToMin, rangeToMax) = (rangeToMin, rangeToMax, rangeFromMin, rangeFromMax)
                } else {
                    (fromSymbol, toSymbol) = (to, from)
                    saveUnits()
                }
            }

            HStack(spacing: 4) {
                answerBox
                if category.isRange {
                    rangeBoxes(min: $rangeToMin, max: $rangeToMax)
                } else {
                    unitMenu(selection: to) { toSymbol = $0 }
                }
            }

            if let note = conversion?.note {
                Text(note)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .opacity(0.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
        .onAppear {
            loadUnits()
            // Testing: `--convert-input <amount>` fills in the amount, so a snapshot shows an answer.
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "--convert-input"), i + 1 < args.count { input = args[i + 1] }
            // Wait a moment for the bubble to become the key window before focusing.
            DispatchQueue.main.async { inputFocused = true }
        }
        .onChange(of: categoryName) { loadUnits() }
    }

    /// The answer, in a grey box like the calculator's history. Clicking it copies the number.
    private var answerBox: some View {
        Button {
            guard case .success(let answer) = result else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(answer, forType: .string)
            justCopied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
        } label: {
            HStack(spacing: 4) {
                switch result {
                case .success(let answer):
                    Text(answer)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                case .failure(let failure):
                    Text(failure.message)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .opacity(0.7)
                case nil:
                    Text("—")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .opacity(0.3)
                }
                Spacer(minLength: 0)
                if justCopied {
                    Text("Copied!")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy the answer")
    }

    /// A range's two ends, like [ 0 ] – [ 100 ], in place of a unit menu.
    private func rangeBoxes(min: Binding<String>, max: Binding<String>) -> some View {
        HStack(spacing: 3) {
            rangeEnd("min", text: min)
            Text("–")
                .font(.system(size: 12, weight: .bold, design: .rounded))
            rangeEnd("max", text: max)
        }
    }

    private func rangeEnd(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .frame(width: Self.rangeEndWidth)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
            .onExitCommand(perform: onClose) // Esc closes the menu
    }

    private func unitMenu(selection: String, choose: @escaping (String) -> Void) -> some View {
        BubblePopUp(title: selection) {
            ForEach(category.menu, id: \.symbol) { unit in
                // Color symbols speak for themselves, and their names were long.
                Button(category.isColor ? unit.symbol : "\(unit.symbol) · \(unit.name)") {
                    choose(unit.symbol)
                    saveUnits()
                }
            }
        }
        .frame(width: Self.unitMenuWidth)
    }

    // Each category remembers its last two units.
    private var unitsKey: String { "convert.\(category.name).units" }

    private func loadUnits() {
        let saved = UserDefaults.standard.stringArray(forKey: unitsKey) ?? []
        fromSymbol = saved.first ?? category.defaultFrom
        toSymbol = saved.count > 1 ? saved[1] : category.defaultTo
    }

    private func saveUnits() {
        // Called straight after a @State change, so read the new values on the next pass.
        DispatchQueue.main.async {
            UserDefaults.standard.set([from, to], forKey: unitsKey)
        }
    }
}

/// A pop-up menu that looks like the bubble's buttons: a white, outlined box with a ⌄.
private struct BubblePopUp<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8) // so "hsl 0–1" fits
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
