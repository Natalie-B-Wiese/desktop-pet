import SwiftUI

/// The bubble's notes, typed on directly. A blank note sits at the top; typing on it makes it a
/// real note and a new blank one appears above it. Clicking a note edits it in place. Everything
/// saves as it's typed, and Return adds a line.
struct BubbleNotesPage: View {
    let store: NoteStore
    var onClose: () -> Void

    /// The blank note's ID. It becomes the new note's ID once something is typed on it.
    @State private var blankID = UUID()
    @FocusState private var focusedID: Note.ID?
    @State private var listHeight: CGFloat = 0

    /// Past this height the list scrolls instead of making the bubble taller.
    private static let maxListHeight: CGFloat = 260
    private static let font = Font.system(size: 12, weight: .medium, design: .rounded)
    /// TextEditor's own inset before the text starts, matched by the sizing text.
    private static let editorInset: CGFloat = 5

    var body: some View {
        // Always a ScrollView (even when short) so the note being typed on is never rebuilt
        // and never loses the keyboard when the list starts scrolling.
        ScrollView {
            VStack(spacing: 4) {
                ForEach([Note(id: blankID, text: "")] + store.notes) { note in
                    row(note)
                }
            }
            .padding(1) // keeps the outlines from being clipped at the edges
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .scrollIndicators(.never)
        .frame(height: min(listHeight, Self.maxListHeight))
        .padding(.horizontal, -1)
        .onChange(of: focusedID) { old, _ in
            if let old { store.tidy(old) }
        }
        .onDisappear {
            if let id = focusedID { store.tidy(id) }
        }
    }

    private func row(_ note: Note) -> some View {
        let isBlank = note.id == blankID
        let isFocused = focusedID == note.id
        return HStack(alignment: .top, spacing: 4) {
            editor(note, isBlank: isBlank)

            if isBlank {
                Color.clear.frame(width: 18, height: 18) // lines up with the ✕ on real notes
            } else {
                Button {
                    store.delete(note.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .opacity(0.5)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete note")
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 1, green: 0.97, blue: 0.8)) // sticky-note yellow
                .onTapGesture { focusedID = note.id } // clicking the note's margin types on it too
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
            isFocused ? Color.black : Color.black.opacity(0.25),
            lineWidth: isFocused ? 2 : 1.5
        ))
    }

    /// A TextEditor exactly as tall as its text: an invisible copy of the text sets the height.
    private func editor(_ note: Note, isBlank: Bool) -> some View {
        Text(sizingText(note.text))
            .font(Self.font)
            .padding(.horizontal, Self.editorInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay {
                TextEditor(text: Binding(
                    get: { note.text },
                    set: { text in type(text, on: note.id) }
                ))
                .font(Self.font)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($focusedID, equals: note.id)
                .onExitCommand(perform: onClose) // Esc closes the menu
            }
            .overlay(alignment: .topLeading) {
                if isBlank {
                    Text("New note")
                        .font(Self.font)
                        .opacity(0.35)
                        .padding(.leading, Self.editorInset)
                        .allowsHitTesting(false)
                }
            }
    }

    /// The text that sizes an editor. A trailing empty line (or no text at all) still takes a line.
    private func sizingText(_ text: String) -> String {
        text.isEmpty || text.hasSuffix("\n") ? text + " " : text
    }

    private func type(_ text: String, on id: Note.ID) {
        let text = String(text.prefix(NoteStore.maxLength))
        if id == blankID {
            guard !text.isEmpty else { return }
            store.add(id: id, text: text)
            blankID = UUID() // a fresh blank note appears above; typing carries on here
        } else {
            store.update(id, text: text)
        }
    }
}
