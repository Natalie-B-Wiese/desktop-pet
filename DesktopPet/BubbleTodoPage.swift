import AppKit
import SwiftUI

/// The bubble's to-do list: add at the top, click a box to check an item off, click the text to edit it.
struct BubbleTodoPage: View {
    let store: TodoStore
    var onClose: () -> Void

    @State private var newText = ""
    @FocusState private var addFocused: Bool
    /// The to-do being edited in place, if any.
    @FocusState private var editingID: Todo.ID?

    /// Past this many rows the list scrolls instead of making the bubble taller.
    private static let maxVisibleRows = 6
    fileprivate static let rowHeight: CGFloat = 30
    private static let rowSpacing: CGFloat = 4

    var body: some View {
        VStack(spacing: 6) {

            TextField("Add a to-do", text: Binding(
                get: { newText },
                set: { newText = String($0.prefix(TodoStore.maxLength)) }
            ))
            .bubbleFieldStyle()
            .focused($addFocused)
            .onSubmit {
                store.add(newText)
                newText = ""
                addFocused = true // ready for the next one
            }
            .onExitCommand(perform: onClose) // Esc closes the menu

            if store.todos.isEmpty {
                Text("Nothing to do!")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.55)
                    .padding(.vertical, 4)
            } else if store.todos.count > Self.maxVisibleRows {
                ScrollView {
                    rows
                        .padding(1) // keeps the row outlines from being clipped at the edges
                }
                .scrollIndicators(.never) // a scroll bar would squeeze the rows narrower
                .frame(height: CGFloat(Self.maxVisibleRows) * (Self.rowHeight + Self.rowSpacing))
                .padding(.horizontal, -1)
            } else {
                rows
            }

        }
        .onChange(of: editingID) { old, _ in
            if let old { store.tidy(old) } // trims an edited to-do, or deletes it if emptied
        }
        .onDisappear {
            if let id = editingID { store.tidy(id) }
        }
    }

    private var rows: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(store.todos) { todo in
                TodoRow(
                    todo: todo,
                    focusedID: $editingID,
                    onToggle: { store.toggle(todo.id) },
                    onType: { store.update(todo.id, text: $0) },
                    onDelete: { store.delete(todo.id) },
                    onClose: onClose
                )
            }
        }
    }
}

/// One to-do: the box checks it off, and clicking the text edits it in place.
private struct TodoRow: View {
    let todo: Todo
    var focusedID: FocusState<Todo.ID?>.Binding
    var onToggle: () -> Void
    var onType: (String) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    /// The field's own copy of the text, so the cursor doesn't jump while typing (like Notes).
    @State private var text: String

    private static let font = Font.system(size: 12, weight: .medium, design: .rounded)

    init(todo: Todo, focusedID: FocusState<Todo.ID?>.Binding, onToggle: @escaping () -> Void,
         onType: @escaping (String) -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.todo = todo
        self.focusedID = focusedID
        self.onToggle = onToggle
        self.onType = onType
        self.onDelete = onDelete
        self.onClose = onClose
        _text = State(initialValue: todo.text)
    }

    var body: some View {
        let isEditing = focusedID.wrappedValue == todo.id
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: todo.isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(todo.isDone ? 0.45 : 1)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(todo.isDone ? "Mark as not done" : "Check off")

            ZStack(alignment: .leading) {
                // The field is always there so clicking the text can focus it, but it's only
                // shown while editing. Otherwise the plain text shows, which can strike through
                // and wraps long names more nicely.
                TextField("", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Self.font)
                    .focused(focusedID, equals: todo.id)
                    .onSubmit { focusedID.wrappedValue = nil } // Return finishes editing
                    .onExitCommand(perform: onClose) // Esc closes the menu
                    .opacity(isEditing ? 1 : 0)
                    .frame(maxHeight: isEditing ? nil : 0) // only the plain text sizes the row
                    .clipped()

                if !isEditing {
                    Text(Self.wrappable(todo.text))
                        .font(Self.font)
                        .strikethrough(todo.isDone)
                        .opacity(todo.isDone ? 0.45 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { focusedID.wrappedValue = todo.id }
                        .help("Edit")
                }
            }
            .padding(.vertical, 6)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.5)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(minHeight: BubbleTodoPage.rowHeight)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
            isEditing ? Color.black : Color.black.opacity(0.25),
            lineWidth: isEditing ? 2 : 1.5
        ))
        .onChange(of: text) { _, newText in
            let limited = String(newText.replacingOccurrences(of: "\n", with: " ").prefix(TodoStore.maxLength))
            if limited != newText { text = limited; return }
            if limited != todo.text { onType(limited) }
        }
        .onChange(of: isEditing) { _, editing in
            // macOS selects all of a field's text when it's focused, so the first keystroke
            // would replace the to-do. Put the cursor at the end instead.
            guard editing else { return }
            DispatchQueue.main.async {
                (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil)
            }
        }
        .onChange(of: todo.text) { _, saved in
            if saved != text { text = saved } // e.g. trimmed after editing
        }
    }

    /// Lets long names like `aspire_opportunity_services` wrap after an underscore or slash
    /// instead of mid-word. Only changes how the text is drawn, not what's saved.
    private static func wrappable(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "_\u{200B}")
            .replacingOccurrences(of: "/", with: "/\u{200B}")
    }
}
