import SwiftUI

/// The bubble's "Reminders" page: the next few reminders, with Add and a link to the full window.
struct BubbleRemindersPage: View {
    let store: ReminderStore
    var onAdd: () -> Void
    var onOpenWindow: () -> Void

    /// More than this and the bubble gets too tall; the rest are in the Reminders window.
    private static let maxShown = 4

    var body: some View {
        let upcoming = store.upcoming
        VStack(spacing: 6) {

            if upcoming.isEmpty {
                Text("No reminders yet")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.55)
                    .padding(.vertical, 4)
            } else {
                ForEach(upcoming.prefix(Self.maxShown)) { reminder in
                    row(reminder)
                }
                if upcoming.count > Self.maxShown {
                    Text("+\(upcoming.count - Self.maxShown) more in the Reminders window")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
            }

            BubbleButton("Add reminder", systemImage: "plus", action: onAdd)
            BubbleButton("Open Reminders window", systemImage: "list.bullet", action: onOpenWindow)
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(ReminderStore.timeText(reminder.date))
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                if let text = reminder.message {
                    Text(text)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.65)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
            Button {
                store.delete(reminder.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete reminder")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }
}

/// The bubble's "Remind me at…" page.
struct BubbleAddReminderPage: View {
    let store: ReminderStore
    var onAdded: () -> Void
    var onClose: () -> Void

    @State private var time = ReminderStore.defaultTime()
    @State private var message = ""
    @FocusState private var timeFocused: Bool

    var body: some View {
        VStack(spacing: 8) {

            VStack(spacing: 2) {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.large)
                    .focused($timeFocused)
                Text(ReminderStore.dayWord(for: time))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.55)
            }

            TextField("Message (optional)", text: Binding(
                get: { message },
                set: { message = String($0.prefix(ReminderStore.maxMessageLength)) }
            ))
            .bubbleFieldStyle()
            .onSubmit(add) // Return adds it

            BubbleButton("Add", systemImage: "bell.badge", action: add)
        }
        .onAppear {
            // Wait a moment for the bubble to become the key window before focusing.
            DispatchQueue.main.async { timeFocused = true }
        }
        .onExitCommand(perform: onClose) // Esc closes the menu
    }

    private func add() {
        store.add(at: time, message: ReminderStore.cleanMessage(message))
        onAdded()
    }
}

/// What the bubble shows when a reminder comes due.
struct BubbleReminderAlert: View {
    let reminder: Reminder
    /// How many more are waiting after this one.
    let moreCount: Int

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(reminder.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            }
            Text(reminder.message ?? "Reminder!")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)
                .fixedSize(horizontal: false, vertical: true)
            Text(moreCount > 0 ? "Click to close · \(moreCount) more" : "Click to close")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }
}
