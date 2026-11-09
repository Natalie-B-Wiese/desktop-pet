import AppKit
import SwiftUI

/// The bubble's notes, typed on directly. A blank note sits at the top; typing on it makes it a
/// real note and a new blank one appears above it. Clicking a note edits it in place. Everything
/// saves as it's typed, and Return adds a line. Long notes fold to their first lines, each with its own ▾.
struct BubbleNotesPage: View {
    let store: NoteStore
    var onClose: () -> Void

    /// The blank note's ID. It becomes the new note's ID once something is typed on it.
    @State private var blankID = UUID()
    @FocusState private var focusedID: Note.ID?
    @State private var listHeight: CGFloat = 0
    /// Notes deleted with ✕, shown as Undo rows until the page closes.
    @State private var deleted = DeletedRows<Note>()
    /// Long notes opened with ▾ (or by typing on them). Each opens and folds on its own, and they stay open
    /// until folded with ▴ or the page closes, so the list doesn't jump when you click away.
    @State private var unfolded: Set<Note.ID> = []

    /// Past this height the list scrolls instead of making the bubble taller.
    private static let maxListHeight: CGFloat = 260

    var body: some View {
        // Always a ScrollView (even when short) so the note being typed on is never rebuilt
        // and never loses the keyboard when the list starts scrolling.
        ScrollView {
            VStack(spacing: 4) {
                ForEach(shownRows) { row in
                    switch row {
                    case .item(let note):
                        self.row(note)
                    case .deleted(let gone):
                        UndoRow(text: Self.firstLine(gone.item.text)) {
                            store.undoDelete(gone.item, at: gone.index)
                            deleted.remove(gone.id)
                        }
                        .padding(.leading, 15) // lines up with the notes, past their reorder arrows
                    }
                }
            }
            .padding(1) // keeps the outlines from being clipped at the edges
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .scrollIndicators(.never)
        .frame(height: min(listHeight, Self.maxListHeight))
        .padding(.horizontal, -1)
        .onChange(of: focusedID) { old, new in
            if let old { store.tidy(old) }
            if let new { unfolded.insert(new) } // typing on a folded note opens it
        }
        .onAppear {
            // `--unfold-note <n>` opens note n (1 = top), since clicks can't be posted from the shell.
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--unfold-note"), args.indices.contains(i + 1), let n = Int(args[i + 1]),
               store.notes.indices.contains(n - 1) {
                unfolded.insert(store.notes[n - 1].id)
            }
        }
        .onDisappear {
            if let id = focusedID { store.tidy(id) }
        }
        .testDeletes(delete: { row in
            if store.notes.indices.contains(row - 1) { delete(store.notes[row - 1]) }
        }, undo: { if let gone = deleted.all.first { store.undoDelete(gone.item, at: gone.index); deleted.remove(gone.id) } })
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 3) {
            // Room for the reorder arrows, which sit outside the note on the far left, like the clipboard's.
            Color.clear.frame(width: 12)

            NoteRow(
                note: note,
                isBlank: note.id == blankID,
                focusedID: $focusedID,
                isUnfolded: unfolded.contains(note.id),
                onToggleFold: { if unfolded.remove(note.id) == nil { unfolded.insert(note.id) } },
                onType: { type($0, on: note.id) },
                onDelete: { delete(note) },
                onClose: onClose
            )
        }
        // An overlay, so the arrows never make a row taller: centered on a short note, and by the first lines
        // of a tall one rather than drifting down its middle. The blank note always stays on top, so it has none.
        .overlay(alignment: .topLeading) {
            if note.id != blankID {
                CaretStepper(
                    canIncrement: store.canMove(note.id, by: -1),
                    canDecrement: store.canMove(note.id, by: 1),
                    increment: { store.move(note.id, by: -1) },
                    decrement: { store.move(note.id, by: 1) },
                    repeatsWhenHeld: false, // one spot per click
                    outlined: false
                )
                .help("Move up or down")
                .frame(width: 12)
                .frame(maxHeight: 44)
            }
        }
    }

    private var shownRows: [DeletedRows<Note>.Row] {
        deleted.merged(with: [Note(id: blankID, text: "")] + store.notes)
    }

    private func delete(_ note: Note) {
        let shown = shownRows
        if let index = store.delete(note.id) { deleted.add(note, index: index, shown: shown) }
    }

    private static func firstLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
    }

    private func type(_ text: String, on id: Note.ID) {
        if id == blankID {
            guard !text.isEmpty else { return }
            store.add(id: id, text: text)
            blankID = UUID() // a fresh blank note appears above; typing carries on here
        } else {
            store.update(id, text: text)
        }
    }
}

/// One note, typed on in place.
private struct NoteRow: View {
    let note: Note
    let isBlank: Bool
    var focusedID: FocusState<Note.ID?>.Binding
    let isUnfolded: Bool
    var onToggleFold: () -> Void
    var onType: (String) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    /// The editor's own copy of the text. Feeding the editor straight from the store makes
    /// macOS move the cursor to the end after every keystroke.
    @State private var text: String
    /// Shows a checkmark on the copy button for a moment after copying.
    @State private var justCopied = false

    private static let font = Font.system(size: 12, weight: .medium, design: .rounded)
    /// TextEditor's own inset before the text starts, matched by the sizing text.
    private static let editorInset: CGFloat = 5

    /// The text's full height and one line's, to fold long notes and count their lines.
    @State private var fullHeight: CGFloat = 0
    @State private var lineHeight: CGFloat = 0

    /// A note longer than this many lines folds to `foldedLines`. Folding only kicks in two lines past it,
    /// so ▾ never hides just a line.
    private static let foldedLines = 6

    init(note: Note, isBlank: Bool, focusedID: FocusState<Note.ID?>.Binding, isUnfolded: Bool, onToggleFold: @escaping () -> Void,
         onType: @escaping (String) -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.note = note
        self.isBlank = isBlank
        self.focusedID = focusedID
        self.isUnfolded = isUnfolded
        self.onToggleFold = onToggleFold
        self.onType = onType
        self.onDelete = onDelete
        self.onClose = onClose
        _text = State(initialValue: note.text)
    }

    var body: some View {
        let isFocused = focusedID.wrappedValue == note.id
        VStack(spacing: 2) {
            if !isBlank { topLine }
            editor
            if isLong && !isBlank { foldButton }
            if text.count >= NoteStore.maxLength {
                // The only time the cap shows: say why typing stopped.
                Text("Notes stop at \(NoteStore.maxLength.formatted()) characters")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Self.yellow)
                .onTapGesture { focusedID.wrappedValue = note.id } // clicking the note's margin types on it too
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
            isFocused ? Color.black : Color.black.opacity(0.25),
            lineWidth: isFocused ? 2 : 1.5
        ))
        .onChange(of: text) { _, newText in
            let limited = String(newText.prefix(NoteStore.maxLength))
            if limited != newText { text = limited; return }
            if limited != note.text { onType(limited) }
        }
        .onChange(of: note.text) { _, saved in
            if saved != text { text = saved } // e.g. trimmed after typing stopped
        }
    }

    /// The note's top line: a small copy button, when it was last edited (`Today 2:30 PM`) in grey, and ✕ on the right.
    private var topLine: some View {
        HStack(spacing: 5) {
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text.trimmingCharacters(in: .whitespacesAndNewlines), forType: .string)
                justCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
            } label: {
                Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .background(RoundedRectangle(cornerRadius: 4).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy note")

            Text(Self.dateText(note.shownDate))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .opacity(0.45)
                .help(Self.dateHelp(note))
            Spacer(minLength: 0)
            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.5)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete note")
        }
        .padding(.leading, Self.editorInset)
    }

    /// `Today 2:30 PM`, `Yesterday 9:05 AM`, `Mon, Nov 2`, or `Nov 2, 2025` from another year.
    static func dateText(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(AppPreferences.clockText(date))" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(AppPreferences.clockText(date))"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// On hover: when it was edited and written, with times.
    private static func dateHelp(_ note: Note) -> String {
        func full(_ date: Date) -> String {
            date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()) + " at " + AppPreferences.clockText(date)
        }
        guard let edited = note.editedAt else { return "Written \(full(note.createdAt))" }
        return "Edited \(full(edited))\nWritten \(full(note.createdAt))"
    }

    /// How many lines the text takes, as wrapped.
    private var lineCount: Int {
        lineHeight > 0 ? Int((fullHeight / lineHeight).rounded()) : 0
    }

    private var isLong: Bool { lineCount > Self.foldedLines + 1 }

    private var isFolded: Bool { isLong && !isUnfolded && !isBlank }

    /// "▾ 12 lines" under a folded note, "▴ Fold" under an open one.
    private var foldButton: some View {
        Button(action: onToggleFold) {
            HStack(spacing: 4) {
                Image(systemName: isFolded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 8, weight: .heavy))
                Text(isFolded ? "\(lineCount) lines" : "Fold")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .opacity(0.55)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isFolded ? "Show all of it" : "Fold it to its first lines")
    }

    /// A TextEditor exactly as tall as its text: an invisible copy of the text sets the height.
    /// A folded note shows only its first lines, fading out at the bottom.
    private var editor: some View {
        Text(sizingText)
            .font(Self.font)
            .fixedSize(horizontal: false, vertical: true) // its full height, even while the note is folded
            .padding(.horizontal, Self.editorInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
            .background {
                Text("X").font(Self.font).fixedSize().hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { lineHeight = $0 }
            }
            .overlay {
                TextEditor(text: $text)
                    .font(Self.font)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .focused(focusedID, equals: note.id)
                    .onExitCommand(perform: onClose) // Esc closes the menu
                    .overlay { NoteLinkStyler(text: text).allowsHitTesting(false) } // underlines links; ⌘-click opens them
            }
            .overlay(alignment: .topLeading) {
                if isBlank && text.isEmpty {
                    Text("New note")
                        .font(Self.font)
                        .opacity(0.35)
                        .padding(.leading, Self.editorInset)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: isFolded ? lineHeight * CGFloat(Self.foldedLines) : nil, alignment: .top)
            .clipped()
            .overlay(alignment: .bottom) {
                if isFolded {
                    LinearGradient(colors: [Self.yellow.opacity(0), Self.yellow], startPoint: .top, endPoint: .bottom)
                        .frame(height: lineHeight * 1.5)
                        .allowsHitTesting(false)
                }
            }
    }

    static let yellow = Color(red: 1, green: 0.97, blue: 0.8) // sticky-note yellow

    /// The text that sizes the editor. A trailing empty line (or no text at all) still takes a line.
    private var sizingText: String {
        text.isEmpty || text.hasSuffix("\n") ? text + " " : text
    }
}
