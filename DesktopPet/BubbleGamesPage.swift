import SwiftUI

/// The Games page: a tile for each game, like the main menu, so more games never crowd it.
struct BubbleGamesPage: View {
    var onOpen: (BubbleMenu.Page) -> Void

    var body: some View {
        HStack(spacing: 6) {
            MenuTile("Spinner", systemImage: "arrow.trianglehead.2.clockwise") { onOpen(.spinner) }
        }
        .frame(maxWidth: .infinity)
    }
}

/// The Spinner game: options typed on directly (a blank "Add option" row sits at the bottom), and Spin runs a
/// highlight down the list that slows to a stop on one, shown big underneath.
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

            if let result = store.result {
                Text(result)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
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
