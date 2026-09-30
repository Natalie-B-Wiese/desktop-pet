import SwiftUI

/// The last few calculations, saved across launches.
@Observable
final class MathHistory {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var equation: String
        var answer: String
    }

    /// Oldest first, so the newest sits right above the input box.
    private(set) var entries: [Entry] = []

    static let limit = 5
    private static let storageKey = "mathHistory"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(equation: String, answer: String) {
        entries.append(Entry(equation: equation, answer: answer))
        entries = Array(entries.suffix(Self.limit))
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

/// The bubble's Math page: a calculator tab and a unit converter tab.
struct BubbleMathPage: View {
    enum Mode: String { case calculator, convert }

    let history: MathHistory
    var onClose: () -> Void

    @AppStorage("mathPage.mode") private var mode = Mode.calculator

    var body: some View {
        VStack(spacing: 8) {
            BubbleTabs(selection: $mode, options: [(.calculator, "Calculator"), (.convert, "Convert")])
            switch mode {
            case .calculator: CalculatorTab(history: history, onClose: onClose)
            case .convert: BubbleConvertTab(onClose: onClose)
            }
        }
    }
}

/// Type an equation, press Return, see the answer.
private struct CalculatorTab: View {
    let history: MathHistory
    var onClose: () -> Void

    @State private var input = ""
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 6) {

            if history.entries.isEmpty {
                Text("Try 2^(3+1) * 5")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.45)
            } else {
                VStack(spacing: 3) {
                    ForEach(history.entries) { entry in
                        historyRow(entry)
                    }
                }
            }

            TextField("Type an equation", text: Binding(
                get: { input },
                set: { newValue in
                    input = newValue
                    // Typing (or pasting) "=" works like pressing Return. Wait until the box has
                    // finished handling the keystroke, or it would put the old text back.
                    if newValue.contains("=") {
                        DispatchQueue.main.async {
                            input = input.replacingOccurrences(of: "=", with: "")
                            calculate()
                        }
                    } else {
                        error = nil // typing again hides the last error
                    }
                }
            ))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
                .focused($inputFocused)
                .onSubmit(calculate) // Return shows the answer
                .onExitCommand(perform: onClose) // Esc closes the menu

            if let error {
                Text(error)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .opacity(0.7)
            }

        }
        .onAppear {
            // Wait a moment for the bubble to become the key window before focusing.
            DispatchQueue.main.async { inputFocused = true }
        }
    }

    /// One past calculation. Clicking it puts the answer back in the box to keep going.
    private func historyRow(_ entry: MathHistory.Entry) -> some View {
        Button {
            input += entry.answer
            inputFocused = true
        } label: {
            HStack(spacing: 4) {
                Text(entry.equation)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .opacity(0.6)
                Spacer(minLength: 4)
                Text("= \(entry.answer)")
                    .lineLimit(1)
                    .fontWeight(.bold)
                    .layoutPriority(1) // the answer matters more than a long equation
            }
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Use this answer")
    }

    private func calculate() {
        let equation = input.trimmingCharacters(in: .whitespaces)
        switch MathEvaluator.evaluate(equation) {
        case .success(let value):
            history.add(equation: equation, answer: MathEvaluator.format(value))
            input = ""
            error = nil
        case .failure(let failure):
            error = failure.message
        }
        inputFocused = true
    }
}
