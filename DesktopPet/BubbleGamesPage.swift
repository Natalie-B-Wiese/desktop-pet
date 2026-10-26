import SwiftUI

/// The Games page: a tile for each game in rows of three, each row centered like the main menu,
/// so more games never crowd it.
struct BubbleGamesPage: View {
    var onOpen: (BubbleMenu.Page) -> Void

    private static let games: [(title: String, systemImage: String, page: BubbleMenu.Page)] = [
        ("Spinner", "arrow.trianglehead.2.clockwise", .spinner),
        ("Number", "42.square", .number),
        ("Groups", "person.3", .groups),
        ("Hide & Seek", "eyes", .hideSeek),
        ("Words", "textformat.abc", .word),
        ("Ask", "questionmark.bubble", .ask),
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

/// The Spinner game: a "List ‹ Custom ›" row on top, then the list's options, and Spin runs a highlight down
/// the list that slows to a stop on one, which stays highlighted. Custom is typed on directly (a blank
/// "Add option" row sits at the bottom); To-dos, Coin and RPS are locked.
struct BubbleSpinnerPage: View {
    let store: SpinnerStore
    var onClose: () -> Void

    /// The blank row's ID. It becomes the new option's ID once something is typed on it.
    @State private var blankID = UUID()
    @FocusState private var focusedID: SpinnerOption.ID?
    @State private var listHeight: CGFloat = 0

    /// Past this height (about 9 rows, for a long to-do list) the list scrolls instead of making the bubble taller.
    private static let maxListHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 8) {
            listPicker

            // Always a ScrollView (like Notes), so the option being typed on is never rebuilt when it starts scrolling.
            ScrollViewReader { scroller in
            ScrollView {
            VStack(spacing: 4) {
                ForEach(rows) { option in
                    SpinnerOptionRow(
                        option: option,
                        number: store.isShuffled ? store.options.firstIndex(of: option).map { $0 + 1 } : nil,
                        isBlank: option.id == blankID,
                        isLocked: store.list.isLocked,
                        isHighlighted: option.id == store.highlightedID,
                        isSpinning: store.isSpinning || store.isShuffling,
                        focusedID: $focusedID,
                        onType: { type($0, on: option.id) },
                        onSubmit: { focusedID = blankID },
                        onDelete: { store.delete(option.id) },
                        onClose: onClose
                    )
                }
            }
            .padding(1) // keeps the outlines from being clipped at the edges
            .animation(.easeInOut(duration: 0.2), value: store.options.map(\.id)) // rows slide while shuffling
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.never) // a scroll bar would squeeze the rows narrower
            .frame(height: min(listHeight, Self.maxListHeight))
            .padding(.horizontal, -1)
            .onChange(of: store.highlightedID) { _, id in
                if let id, listHeight > Self.maxListHeight { scroller.scrollTo(id) } // follow the spin down a long list
            }
            }

            if let hint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .opacity(0.55)
            }

            HStack(spacing: 6) {
                BubbleButton("Spin", systemImage: "arrow.trianglehead.2.clockwise", centered: true) {
                    focusedID = nil
                    store.spin()
                }
                .disabled(!store.canSpin)
                .opacity(store.canSpin || store.isSpinning ? 1 : 0.4)
                // Custom only: mixing up Heads/Tails or Rock/Paper/Scissors means nothing.
                if store.list == .custom {
                    BubbleButton("Shuffle", systemImage: "shuffle", centered: true) {
                        focusedID = nil
                        store.shuffle()
                    }
                    .disabled(!store.canShuffle)
                    .opacity(store.canShuffle || store.isShuffling ? 1 : 0.4)
                    .help("Mix up the order")
                }
            }
        }
        .onChange(of: focusedID) { old, _ in
            if let old { store.tidy(old) }
        }
        .onDisappear {
            if let id = focusedID { store.tidy(id) }
        }
    }

    /// "List  ‹ Custom ›", like the ‹ › rows in Settings.
    private var listPicker: some View {
        HStack(spacing: 0) {
            Text("List")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                HeaderIconButton(systemImage: "chevron.left", help: "Previous list", width: 18) { stepList(-1) }
                Text(store.list.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 56)
                HeaderIconButton(systemImage: "chevron.right", help: "Next list", width: 18) { stepList(1) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
        .allowsHitTesting(!store.isSpinning)
    }

    /// Why there's nothing (much) to spin.
    private var hint: String? {
        switch (store.list, store.options.count) {
        case (.custom, ..<2): "Add at least 2 options to spin"
        case (.todos, 0): "No to-dos left. Nice!"
        case (.todos, 1): "Just one to-do left. That's the one!"
        default: nil
        }
    }

    private func stepList(_ offset: Int) {
        focusedID = nil // tidies the option being typed on
        store.stepList(by: offset)
    }

    /// The options, then (on Custom) the blank row unless the list is full.
    private var rows: [SpinnerOption] {
        let showsBlank = store.list == .custom && store.options.count < SpinnerStore.maxOptions
        return store.options + (showsBlank ? [SpinnerOption(id: blankID, text: "")] : [])
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

/// One option, typed on in place (unless it's a locked preset). Black with white text while the highlight is on it.
private struct SpinnerOptionRow: View {
    let option: SpinnerOption
    /// Its place in a shuffled order (1, 2, 3…), shown before it.
    let number: Int?
    let isBlank: Bool
    /// A preset's option: no typing and no ✕.
    let isLocked: Bool
    /// What the blank row says.
    var placeholder = "Add option"
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

    init(option: SpinnerOption, number: Int? = nil, isBlank: Bool, isLocked: Bool, placeholder: String = "Add option",
         isHighlighted: Bool = false, isSpinning: Bool,
         focusedID: FocusState<SpinnerOption.ID?>.Binding, onType: @escaping (String) -> Void,
         onSubmit: @escaping () -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.option = option
        self.number = number
        self.isBlank = isBlank
        self.isLocked = isLocked
        self.placeholder = placeholder
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
            if let number {
                Text("\(number).")
                    .font(Self.font.monospacedDigit())
                    .foregroundStyle(isHighlighted ? .white : .black)
                    .opacity(0.5)
            }
            if isLocked {
                // Plain text, so a preset never takes the keyboard (a text field would, even locked).
                Text(option.text)
                    .font(Self.font)
                    .foregroundStyle(isHighlighted ? .white : .black)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(.black.opacity(0.35)))
                    .textFieldStyle(.plain)
                    .font(Self.font)
                    .foregroundStyle(isHighlighted ? .white : .black)
                    .focused(focusedID, equals: option.id)
                    .onSubmit(onSubmit)
                    .onExitCommand(perform: onClose) // Esc closes the menu
            }

            if isBlank || isLocked {
                Color.clear.frame(width: 18, height: 18) // as tall as a row with ✕, and lines up with it
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
        .allowsHitTesting(!isSpinning && !isLocked) // no editing mid-spin (the list stays put and keeps its look) or on presets
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHighlighted ? Color.black : .white)
                .onTapGesture { if !isLocked { focusedID.wrappedValue = option.id } }
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

/// The Number game's answer, big and bold; a faint "?" before the first one.
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

/// Ask Topsy, a Magic 8-Ball: her answer on top, typed out like her chatter, and Ask under it.
struct BubbleAskPage: View {
    let game: AskGame

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if game.isThinking {
                    Text("Hmm\u{2026}")
                        .opacity(0.4)
                } else if let answer = game.answer {
                    TypewriterText(text: answer, start: game.answerStart)
                } else {
                    Text("Think of a yes-or-no question")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .opacity(0.45)
                }
            }
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44) // room for a two-line answer, so the bubble doesn't jump
            BubbleButton("Ask", centered: true) { game.ask() }
        }
        .onDisappear(perform: game.reset) // leaving the page (‹, ✕ or clicking her) starts the next visit fresh
    }
}

/// Hide and Seek: Hide sends her off to hide in one of your open apps (the bubble goes with her), where you click her to find her.
struct BubbleHideSeekPage: View {
    let game: HideAndSeek

    var body: some View {
        VStack(spacing: 8) {
            Text("I'll hide in one of your open apps. Find me and click me!")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let problem = game.problem {
                Text(problem)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0.55)
            }
            BubbleButton("Hide", centered: true) { game.start() }
            Text("Stuck? Give up from the menu bar.")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
        .onDisappear(perform: game.clearProblem)
    }
}

/// Guess the Word: the category, the word as blanks, six paw prints (one goes faint per wrong letter), her
/// reaction, and the letters to click. Letters can be typed too, and Return deals the next word once it's over.
struct BubbleWordPage: View {
    let game: WordGame
    var onClose: () -> Void

    @FocusState private var focused: Bool

    private static let letterRows = ["ABCDEFG", "HIJKLMN", "OPQRSTU", "VWXYZ"]

    var body: some View {
        VStack(spacing: 8) {
            Text(game.category)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .opacity(0.55)

            HStack(spacing: 4) {
                ForEach(Array(game.word.enumerated()), id: \.offset) { _, letter in
                    let shown = game.guessed.contains(letter) || game.isLost
                    Text(shown ? String(letter) : " ")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        // Letters she had to reveal are faint.
                        .opacity(game.guessed.contains(letter) ? 1 : 0.35)
                        .frame(width: 18, height: 22)
                        .overlay(alignment: .bottom) { Rectangle().frame(height: 2) }
                }
            }

            HStack(spacing: 6) {
                ForEach(0..<WordGame.lives, id: \.self) { index in
                    let lost = index >= WordGame.lives - game.misses
                    Image(systemName: lost ? "pawprint" : "pawprint.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(lost ? 0.3 : 1)
                }
            }
            .help("Wrong letters left")

            Group {
                if let reaction = game.reaction {
                    TypewriterText(text: reaction, start: game.reactionStart)
                } else {
                    Text("Guess a letter!").opacity(0.45)
                }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 32) // room for two lines, so the letters don't jump

            if game.isOver {
                BubbleButton("Next word", centered: true) { game.newWord() }
            } else {
                VStack(spacing: 4) {
                    ForEach(Self.letterRows, id: \.self) { row in
                        HStack(spacing: 4) {
                            ForEach(Array(row), id: \.self) { letterButton($0) }
                        }
                    }
                }
            }
        }
        // Typing works too. The page takes the keyboard as it opens.
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear {
            game.dealIfNeeded()
            focused = true
        }
        .onKeyPress(phases: .down) { press in
            if press.key == .return, game.isOver {
                game.newWord()
                return .handled
            }
            guard let letter = press.characters.first, letter.isLetter else { return .ignored }
            game.guess(letter)
            return .handled
        }
        .onExitCommand(perform: onClose) // Esc closes the menu
    }

    /// Black once guessed right, faint and crossed out once guessed wrong.
    private func letterButton(_ letter: Character) -> some View {
        let guessed = game.guessed.contains(letter)
        let right = guessed && game.word.contains(letter)
        return Button { game.guess(letter) } label: {
            Text(String(letter))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(right ? .white : .black)
                .strikethrough(guessed && !right)
                .frame(width: 26, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(right ? Color.black : .white))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(guessed ? 0.25 : 1), lineWidth: 1.5))
                .opacity(guessed && !right ? 0.35 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!guessed) // not `.disabled`, which greys out the black right letters
    }
}

/// The Groups game: "Number of groups ‹ 2 ›" on top, then either the items to split (typed on directly, like the
/// Spinner's Custom list, with a blank "Add item" row at the bottom) and Make groups, or the groups made, with Again
/// and Edit items. Both scroll once they're long.
struct BubbleGroupsPage: View {
    let store: GroupsStore
    var onClose: () -> Void

    /// The blank row's ID. It becomes the new item's ID once something is typed on it.
    @State private var blankID = UUID()
    @FocusState private var focusedID: SpinnerOption.ID?
    @State private var listHeight: CGFloat = 0

    /// Past this height (about 9 rows) the list, or the groups, scroll instead of making the bubble taller.
    private static let maxListHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 8) {
            countPicker

            if let groups = store.groups {
                capped {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6, alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 6) {
                        ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                            groupBox(index + 1, group)
                        }
                    }
                }
                HStack(spacing: 6) {
                    BubbleButton("Again", systemImage: "shuffle", centered: true) { store.make() }
                    BubbleButton("Edit items", systemImage: "pencil", centered: true) { store.editItems() }
                }
                .allowsHitTesting(!store.isMaking)
            } else {
                capped {
                    VStack(spacing: 4) {
                        ForEach(rows) { item in
                            SpinnerOptionRow(
                                option: item,
                                isBlank: item.id == blankID,
                                isLocked: false,
                                placeholder: "Add item",
                                isSpinning: false,
                                focusedID: $focusedID,
                                onType: { type($0, on: item.id) },
                                onSubmit: { focusedID = blankID },
                                onDelete: { store.delete(item.id) },
                                onClose: onClose
                            )
                        }
                    }
                }
                if store.items.count < store.groupCount {
                    Text("Add at least \(store.groupCount) items for \(store.groupCount) groups")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
                BubbleButton("Make groups", systemImage: "person.3", centered: true) {
                    focusedID = nil
                    store.make()
                }
                .disabled(!store.canMake)
                .opacity(store.canMake ? 1 : 0.4)
            }
        }
        .onChange(of: focusedID) { old, _ in
            if let old { store.tidy(old) }
        }
        .onDisappear {
            if let id = focusedID { store.tidy(id) }
        }
    }

    /// Always a ScrollView (like Notes), so the item being typed on is never rebuilt when it starts scrolling.
    private func capped<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            content()
                .padding(1) // keeps the outlines from being clipped at the edges
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .scrollIndicators(.never) // a scroll bar would squeeze the rows narrower
        .frame(height: min(listHeight, Self.maxListHeight))
        .padding(.horizontal, -1)
    }

    /// "Number of groups  ‹ 2 ›", like the Spinner's List row. Changing it while groups show remakes them.
    private var countPicker: some View {
        HStack(spacing: 0) {
            Text("Number of groups")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                HeaderIconButton(systemImage: "chevron.left", help: "Fewer groups", width: 18) { step(-1) }
                Text("\(store.groupCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .frame(width: 24)
                HeaderIconButton(systemImage: "chevron.right", help: "More groups", width: 18) { step(1) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
        .allowsHitTesting(!store.isMaking)
    }

    private func groupBox(_ number: Int, _ items: [SpinnerOption]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Group \(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.bottom, 2)
            ForEach(items) { item in
                Text(item.text)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }

    private func step(_ offset: Int) {
        focusedID = nil // tidies the item being typed on
        store.stepGroupCount(by: offset)
    }

    /// The items, then the blank row unless the list is full.
    private var rows: [SpinnerOption] {
        store.items + (store.items.count < GroupsStore.maxItems ? [SpinnerOption(id: blankID, text: "")] : [])
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
