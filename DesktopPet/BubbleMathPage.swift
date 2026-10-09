import SwiftUI

/// The last few calculations, saved across launches. The Calculator and Time tabs each keep one.
@Observable
final class MathHistory {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var equation: String
        var answer: String
        /// What clicking the entry types back in, when that differs from the answer.
        var reuse: String?
    }

    /// Oldest first, so the newest sits right above the input box.
    private(set) var entries: [Entry] = []

    static let limit = 5
    private let storageKey: String

    init(storageKey: String = "mathHistory") {
        self.storageKey = storageKey
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    func add(equation: String, answer: String, reuse: String? = nil) {
        entries.append(Entry(equation: equation, answer: answer, reuse: reuse == answer ? nil : reuse))
        entries = Array(entries.suffix(Self.limit))
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

/// The bubble's Math page: calculator, unit converter and time math tabs.
struct BubbleMathPage: View {
    enum Mode: String { case calculator, convert, time }

    let history: MathHistory
    let timeHistory: MathHistory
    var onClose: () -> Void

    @AppStorage("mathPage.mode") private var mode = Mode.calculator

    var body: some View {
        VStack(spacing: 8) {
            BubbleTabs(selection: $mode, options: [(.calculator, "Calculator"), (.convert, "Convert"), (.time, "Time")])
            switch mode {
            case .calculator:
                CalculatorTab(history: history, placeholder: "Type an equation", hint: "Try 2^(3+1) * 5",
                              onClose: onClose) { equation in
                    MathEvaluator.evaluate(equation)
                        .map { (MathEvaluator.format($0), nil) }
                        .mapError { CalculatorTab.Failure(message: $0.message) }
                }
            case .convert:
                BubbleConvertTab(onClose: onClose)
            case .time:
                // Adds and subtracts in hours and minutes, like "1:45 + 2:30" or "9am + 2:15".
                CalculatorTab(history: timeHistory, placeholder: "Type times", hint: "Try 1:45 + 2:30 or 9am + 50m",
                              onClose: onClose) { equation in
                    TimeEvaluator.evaluate(equation)
                        .map { ($0.text, $0.reuse) }
                        .mapError { CalculatorTab.Failure(message: $0.message) }
                }
                .id(Mode.time) // its own text box, not the calculator's
            }
        }
    }
}

/// Type an equation, press Return, see the answer. The Calculator and Time tabs both use it.
private struct CalculatorTab: View {
    struct Failure: Error { var message: String }

    let history: MathHistory
    let placeholder: String
    let hint: String
    var onClose: () -> Void
    /// The answer to show, plus what clicking it types back in (nil means the answer itself).
    let evaluate: (String) -> Result<(String, String?), Failure>

    @State private var input = ""
    @State private var error: String?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 6) {

            if history.entries.isEmpty {
                Text(hint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.45)
            } else {
                VStack(spacing: 3) {
                    ForEach(history.entries) { entry in
                        historyRow(entry)
                    }
                }
            }

            TextField(placeholder, text: Binding(
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
            input += entry.reuse ?? entry.answer
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
        switch evaluate(equation) {
        case .success(let (answer, reuse)):
            history.add(equation: equation, answer: answer, reuse: reuse)
            input = ""
            error = nil
        case .failure(let failure):
            error = failure.message
        }
        inputFocused = true
    }
}
