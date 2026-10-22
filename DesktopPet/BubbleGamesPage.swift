import SwiftUI

/// The Games page: a tile for each game in rows of three, each row centered like the main menu,
/// so more games never crowd it.
struct BubbleGamesPage: View {
    var onOpen: (BubbleMenu.Page) -> Void

    private static let games: [(title: String, systemImage: String, page: BubbleMenu.Page)] = [
        ("Spinner", "arrow.trianglehead.2.clockwise", .spinner),
        ("Number", "42.square", .number),
        ("Coin", "dollarsign.circle", .coin),
        ("RPS", "scissors", .rockPaperScissors),
    ]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Array(stride(from: 0, to: Self.games.count, by: 3)), id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(Self.games[start..<min(start + 3, Self.games.count)], id: \.title) { game in
                        MenuTile(game.title, systemImage: game.systemImage) { onOpen(game.page) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The Spinner game: options typed on directly (a blank "Add option" row sits at the bottom), and Spin runs a
/// highlight down the list that slows to a stop on one, which stays highlighted.
struct BubbleSpinnerPage: View {
    let store: SpinnerStore
    var onClose: () -> Void

    /// The blank row's ID. It becomes the new option's ID once something is typed on it.
    @State private var blankID = UUID()
    @FocusState private var focusedID: SpinnerOption.ID?

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                ForEach(rows) { option in
                    SpinnerOptionRow(
                        option: option,
                        isBlank: option.id == blankID,
                        isHighlighted: option.id == store.highlightedID,
                        isSpinning: store.isSpinning,
                        focusedID: $focusedID,
                        onType: { type($0, on: option.id) },
                        onSubmit: { focusedID = blankID },
                        onDelete: { store.delete(option.id) },
                        onClose: onClose
                    )
                }
            }
            .padding(1) // keeps the outlines from being clipped at the edges

            if store.options.count < 2 {
                Text("Add at least 2 options to spin")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.55)
            }

            BubbleButton("Spin", systemImage: "arrow.trianglehead.2.clockwise", centered: true) {
                focusedID = nil
                store.spin()
            }
            .disabled(!store.canSpin)
            .opacity(store.canSpin || store.isSpinning ? 1 : 0.4)
        }
        .onChange(of: focusedID) { old, _ in
            if let old { store.tidy(old) }
        }
        .onDisappear {
            if let id = focusedID { store.tidy(id) }
        }
    }

    /// The options, then the blank row unless the list is full.
    private var rows: [SpinnerOption] {
        store.options + (store.options.count < SpinnerStore.maxOptions ? [SpinnerOption(id: blankID, text: "")] : [])
    }

    private func type(_ text: String, on id: SpinnerOption.ID) {
        if id == blankID {
            guard !text.isEmpty else { return }
            store.add(id: id, text: text)
            blankID = UUID() // a fresh blank row appears below; typing carries on here
        } else {
            store.update(id, text: text)
        }
    }
}

/// One option, typed on in place. Black with white text while the highlight is on it.
private struct SpinnerOptionRow: View {
    let option: SpinnerOption
    let isBlank: Bool
    let isHighlighted: Bool
    let isSpinning: Bool
    var focusedID: FocusState<SpinnerOption.ID?>.Binding
    var onType: (String) -> Void
    var onSubmit: () -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    /// The field's own copy of the text, so the store never moves the cursor (like Notes).
    @State private var text: String

    private static let font = Font.system(size: 12, weight: .semibold, design: .rounded)

    init(option: SpinnerOption, isBlank: Bool, isHighlighted: Bool, isSpinning: Bool,
         focusedID: FocusState<SpinnerOption.ID?>.Binding, onType: @escaping (String) -> Void,
         onSubmit: @escaping () -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.option = option
        self.isBlank = isBlank
        self.isHighlighted = isHighlighted
        self.isSpinning = isSpinning
        self.focusedID = focusedID
        self.onType = onType
        self.onSubmit = onSubmit
        self.onDelete = onDelete
        self.onClose = onClose
        _text = State(initialValue: option.text)
    }

    var body: some View {
        let isFocused = focusedID.wrappedValue == option.id
        HStack(spacing: 4) {
            TextField("", text: $text, prompt: Text("Add option").foregroundStyle(.black.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(Self.font)
                .foregroundStyle(isHighlighted ? .white : .black)
                .focused(focusedID, equals: option.id)
                .onSubmit(onSubmit)
                .onExitCommand(perform: onClose) // Esc closes the menu

            if isBlank {
                Color.clear.frame(width: 18, height: 18) // lines up with the ✕ on real options
            } else {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .opacity(isHighlighted ? 0.8 : 0.5)
                        .foregroundStyle(isHighlighted ? .white : .black)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete option")
            }
        }
        .allowsHitTesting(!isSpinning) // no editing mid-spin; the list stays put and keeps its look
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHighlighted ? Color.black : .white)
                .onTapGesture { focusedID.wrappedValue = option.id }
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
            isFocused || isHighlighted ? Color.black : Color.black.opacity(0.25),
            lineWidth: isFocused || isHighlighted ? 2 : 1.5
        ))
        .onChange(of: text) { _, newText in
            let limited = String(newText.prefix(SpinnerStore.maxLength))
            if limited != newText { text = limited; return }
            if limited != option.text { onType(limited) }
        }
        .onChange(of: option.text) { _, saved in
            if saved != text { text = saved } // e.g. trimmed after typing stopped
        }
    }
}

/// The Number game: the answer big and bold on top, and [min]–[max] boxes with Roll beside them under it.
/// Return in either box rolls.
struct BubbleNumberPage: View {
    @Bindable var game: NumberGame
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            GameAnswer(text: game.shown)

            HStack(spacing: 6) {
                HStack(spacing: 3) {
                    end("min", text: $game.minText)
                    Text("–")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    end("max", text: $game.maxText)
                }
                .fixedSize() // the Roll button takes the rest, never the "–"
                BubbleButton("Roll", systemImage: "dice", centered: true) { game.roll() }
            }

            if let problem = game.problem {
                Text(problem)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.55)
            }
        }
        .allowsHitTesting(!game.isRolling)
    }

    /// One end of the range, styled like Convert's Range boxes.
    private func end(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = String($0.prefix(NumberGame.maxLength)) }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .frame(width: 52)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
        .onSubmit { game.roll() }
        .onExitCommand(perform: onClose) // Esc closes the menu
    }
}

/// A game that picks one of a few answers (Coin, rock, paper, scissors): the answer big and bold on top,
/// and its button under it.
struct BubblePickPage: View {
    let game: RandomPick
    let button: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            GameAnswer(text: game.shown)
            BubbleButton(button, systemImage: systemImage, centered: true) { game.pick() }
        }
        .allowsHitTesting(!game.isPicking)
    }
}

/// A game's answer, big and bold; a faint "?" before the first one.
private struct GameAnswer: View {
    let text: String?

    var body: some View {
        Text(text ?? "?")
            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .opacity(text == nil ? 0.2 : 1)
            .frame(maxWidth: .infinity)
    }
}
