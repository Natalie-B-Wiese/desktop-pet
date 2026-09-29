import SwiftUI

/// The bubble's to-do list: add at the top, click a box to check an item off.
struct BubbleTodoPage: View {
    let store: TodoStore
    var onBack: () -> Void
    var onClose: () -> Void

    @State private var newText = ""
    @FocusState private var addFocused: Bool

    /// Past this many rows the list scrolls instead of making the bubble taller.
    private static let maxVisibleRows = 6
    private static let rowHeight: CGFloat = 30
    private static let rowSpacing: CGFloat = 4

    var body: some View {
        VStack(spacing: 6) {
            Text("To-dos")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.bottom, 2)

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

            BubbleButton("Back", systemImage: "chevron.left", style: .quiet, action: onBack)
        }
    }

    private var rows: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(store.todos) { todo in
                row(todo)
            }
        }
    }

    private func row(_ todo: Todo) -> some View {
        HStack(spacing: 6) {
            Button {
                store.toggle(todo.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: todo.isDone ? "checkmark.square.fill" : "square")
                        .font(.system(size: 14, weight: .semibold))
                    Text(todo.text)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .strikethrough(todo.isDone)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(todo.isDone ? 0.45 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(todo.isDone ? "Mark as not done" : "Check off")

            Button {
                store.delete(todo.id)
            } label: {
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
        .frame(minHeight: Self.rowHeight)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }
}
