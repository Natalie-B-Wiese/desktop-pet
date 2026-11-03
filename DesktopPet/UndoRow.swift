import SwiftUI

/// Rows deleted on a page, kept so they can be put back. Each one shows as an Undo row in the spot it
/// was deleted from until the page closes (it's the page's `@State`, so leaving the page forgets them).
/// The store has already deleted and saved; Undo puts the item back.
struct DeletedRows<Item: Identifiable> {
    struct Deleted: Identifiable {
        let item: Item
        /// Where it was in the store's list, for putting it back.
        let index: Int
        /// The row drawn right after it when it was deleted (an item or another deleted row),
        /// so it's drawn in the same spot. Nil if it was last.
        let nextID: Item.ID?
        var id: Item.ID { item.id }
    }

    enum Row: Identifiable {
        case item(Item)
        case deleted(Deleted)

        var id: Item.ID {
            switch self {
            case .item(let item): item.id
            case .deleted(let deleted): deleted.id
            }
        }
    }

    private(set) var all: [Deleted] = []

    /// Remembers a row just deleted from `shown`, the rows as drawn right before the delete.
    mutating func add(_ item: Item, index: Int, shown: [Row]) {
        let position = shown.firstIndex { $0.id == item.id }
        let next = position.flatMap { shown.indices.contains($0 + 1) ? shown[$0 + 1].id : nil }
        all.append(Deleted(item: item, index: index, nextID: next))
    }

    /// Forgets a deleted row (after Undo puts it back).
    mutating func remove(_ id: Item.ID) {
        all.removeAll { $0.id == id }
    }

    mutating func removeAll() {
        all.removeAll()
    }

    /// The store's items with the deleted rows back in their spots.
    func merged(with items: [Item]) -> [Row] {
        guard !all.isEmpty else { return items.map(Row.item) }
        let ids = Set(items.map(\.id)).union(all.map(\.id))
        var before: [Item.ID: [Deleted]] = [:]
        var atEnd: [Deleted] = []
        for deleted in all {
            // One whose next row is gone (deleted some other way) goes at the end.
            if let next = deleted.nextID, ids.contains(next) {
                before[next, default: []].append(deleted)
            } else {
                atEnd.append(deleted)
            }
        }
        var rows: [Row] = []
        func addDeleted(before id: Item.ID) {
            for deleted in before[id] ?? [] {
                addDeleted(before: deleted.id)
                rows.append(.deleted(deleted))
            }
        }
        for item in items {
            addDeleted(before: item.id)
            rows.append(.item(item))
        }
        for deleted in atEnd {
            addDeleted(before: deleted.id)
            rows.append(.deleted(deleted))
        }
        return rows
    }
}

/// What's left of a deleted row: a faint dashed outline with ↶ Undo and what it was, faint. Undo sits on the left,
/// away from where the ✕ was, so a double click on ✕ doesn't bring it straight back.
struct UndoRow: View {
    let text: String
    var minHeight: CGFloat = 28
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .labelStyle(UndoLabelStyle())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black, lineWidth: 1.5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Bring it back")

            // Faint, with no "Deleted": the dashed outline and Undo say it. (Not struck through, which means checked off on To-dos.)
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.45)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .frame(minHeight: minHeight)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
    }
}

private struct UndoLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 9, weight: .heavy))
            configuration.title
        }
    }
}

extension Notification.Name {
    /// For testing (`--delete-row <n>`): the page showing deletes its nth row (1 = top) as its ✕ would.
    static let testDeleteRow = Notification.Name("DesktopPet.testDeleteRow")
    /// For testing (`--undo`): the page showing clicks its first Undo row.
    static let testUndo = Notification.Name("DesktopPet.testUndo")
}

extension View {
    /// Lets `--delete-row` and `--undo` press ✕ and Undo on this page, since clicks can't be posted from the shell.
    func testDeletes(delete: @escaping (Int) -> Void, undo: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .testDeleteRow)) { note in
            if let row = note.object as? Int { delete(row) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .testUndo)) { _ in undo() }
    }
}
