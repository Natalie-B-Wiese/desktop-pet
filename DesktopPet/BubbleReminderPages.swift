import SwiftUI

/// The bubble's "Reminders" page: every upcoming reminder (click one to edit it), and Add.
struct BubbleRemindersPage: View {
    let store: ReminderStore
    var onAdd: () -> Void
    var onEdit: (Reminder.ID) -> Void

    /// Past this many rows the list scrolls instead of making the bubble taller.
    private static let maxVisibleRows = 4
    private static let rowHeight: CGFloat = 38
    private static let rowSpacing: CGFloat = 6

    var body: some View {
        let upcoming = store.upcoming
        VStack(spacing: 6) {

            if upcoming.isEmpty {
                Text("No reminders yet")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.55)
                    .padding(.vertical, 4)
            } else if upcoming.count > Self.maxVisibleRows {
                ScrollView {
                    rows(upcoming)
                        .padding(1) // keeps the row outlines from being clipped at the edges
                }
                .scrollIndicators(.never) // a scroll bar would squeeze the rows narrower
                .frame(height: CGFloat(Self.maxVisibleRows) * (Self.rowHeight + Self.rowSpacing))
                .padding(.horizontal, -1)
            } else {
                rows(upcoming)
            }

            BubbleButton("Add reminder", systemImage: "plus", action: onAdd)
        }
    }

    private func rows(_ reminders: [Reminder]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(reminders) { reminder in
                row(reminder)
            }
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        HStack(spacing: 6) {
            Button {
                onEdit(reminder.id)
            } label: {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit reminder")

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
        .frame(minHeight: Self.rowHeight)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }
}

/// The bubble's "Remind me at…" page, also used to edit an existing reminder.
struct BubbleAddReminderPage: View {
    let store: ReminderStore
    /// The reminder being changed, or nil when adding a new one.
    var editing: Reminder? = nil
    var onAdded: () -> Void
    var onClose: () -> Void

    /// 0…23. The hour box shows 1…12 plus AM/PM, or 00…23 with military time on.
    @State private var hour24: Int
    /// The minutes as typed, so the box can be empty while editing; padded to "05" when it loses focus.
    @State private var minuteText: String
    @State private var message: String
    /// Digits typed into the hour box since it was focused; two of them (or one that can't
    /// start a two-digit hour) complete it and move on to the minutes.
    @State private var hourTyped = ""
    /// Set when Backspace goes back to the hour box, so the next digit adds to the hour
    /// that's there ("1" then "3" is 13) instead of starting over.
    @State private var resumeHourTyping = false
    private enum Field { case hour, minute }
    @FocusState private var focusedField: Field?
    @AppStorage(AppPreferences.militaryTimeKey) private var militaryTime = false

    init(store: ReminderStore, editing: Reminder? = nil, onAdded: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.store = store
        self.editing = editing
        self.onAdded = onAdded
        self.onClose = onClose
        let start = Calendar.current.dateComponents([.hour, .minute], from: editing?.date ?? ReminderStore.defaultTime())
        _hour24 = State(initialValue: start.hour ?? 12)
        _minuteText = State(initialValue: String(format: "%02d", start.minute ?? 0))
        _message = State(initialValue: editing?.message ?? "")
    }

    private var minute: Int { Int(minuteText) ?? 0 }

    /// The picked time, today; the store moves it to tomorrow if it has already passed.
    private var time: Date {
        Calendar.current.date(bySettingHour: hour24, minute: minute, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        VStack(spacing: 8) {

            if militaryTime {
                // Red and bold like the Clipboard's "full" warning, so a 12-hour habit doesn't slip through.
                Text("Military time is on")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.top, -4)
            }

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    // Space or ":" in the hour box jumps to the minutes, like Tab.
                    numberBox(hourBinding)
                        .focused($focusedField, equals: .hour)
                        .onKeyPress(characters: CharacterSet(charactersIn: " :")) { _ in
                            focusedField = .minute
                            return .handled
                        }
                        .onKeyPress(characters: .decimalDigits) { press in
                            typeHourDigit(press.characters)
                            return .handled
                        }
                    Text(":")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .offset(y: -2) // sits a touch high, like a clock's colon
                    // Backspace in an empty minutes box goes back to the hour box, selected.
                    numberBox(minuteBinding)
                        .focused($focusedField, equals: .minute)
                        // The Delete key arrives as U+007F, which `.onKeyPress(.delete)` doesn't match.
                        .onKeyPress(characters: CharacterSet(charactersIn: "\u{7F}\u{8}")) { _ in
                            guard minuteText.isEmpty else { return .ignored }
                            resumeHourTyping = true
                            focusedField = .hour
                            return .handled
                        }
                        // The hour may have already jumped here, so a habitual "12:45" or "12 45" still works.
                        .onKeyPress(characters: CharacterSet(charactersIn: " :")) { _ in .handled }
                    if !militaryTime {
                        BubbleTabs(selection: isPM, options: [(false, "AM"), (true, "PM")], vertical: true)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.leading, 6)
                    }
                }
                .fixedSize(horizontal: false, vertical: true) // AM/PM matches the boxes' height

                Text(ReminderStore.dayWord(for: time))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.55)
            }

            TextField("Message (optional)", text: Binding(
                get: { message },
                set: { message = String($0.prefix(ReminderStore.maxMessageLength)) }
            ))
            .bubbleFieldStyle()
            .onSubmit(save) // Return adds or saves it

            if editing == nil {
                BubbleButton("Add", systemImage: "bell.badge", action: save)
            } else {
                BubbleButton("Save", systemImage: "checkmark", action: save)
            }
        }
        .onAppear {
            // Wait a moment for the bubble to become the key window before focusing.
            DispatchQueue.main.async { focusedField = .hour }
        }
        .onChange(of: focusedField) { old, new in
            if old == .minute { minuteText = String(format: "%02d", minute) }
            if new == .hour {
                // Tabbing or clicking in starts the hour over; Backspace from the minutes picks up where it was.
                hourTyped = resumeHourTyping ? String(shownHour) : ""
                resumeHourTyping = false
            }
        }
        .onExitCommand(perform: onClose) // Esc closes the menu
    }

    private var hourRange: ClosedRange<Int> { militaryTime ? 0...23 : 1...12 }

    /// The hour as the box shows it: 0…23, or 1…12 with AM/PM.
    private var shownHour: Int { militaryTime ? hour24 : (hour24 % 12 == 0 ? 12 : hour24 % 12) }

    /// Types one digit into the hour box, then jumps to the minutes once the hour is complete:
    /// after two digits, or after one that no valid hour continues (like "3" with AM/PM).
    private func typeHourDigit(_ digit: String) {
        hourTyped = String((hourTyped + digit).suffix(2))
        if let hour = Self.clockValue(hourTyped, in: hourRange) { setHour(hour) }
        let canContinue = hourTyped.count < 2 && (Int(hourTyped) ?? 0) * 10 <= hourRange.upperBound
        if !canContinue { focusedField = .minute }
    }

    /// Sets the hour as shown in the box (0…23, or 1…12 keeping AM/PM).
    private func setHour(_ hour: Int) {
        hour24 = militaryTime ? hour : hour % 12 + (hour24 >= 12 ? 12 : 0)
    }

    /// The hour box's text: 00…23 with military time, otherwise 1…12 (AM/PM is picked separately).
    private var hourBinding: Binding<String> {
        // Digits are typed by `typeHourDigit`; this handles everything else, like Backspace or pasting.
        Binding(
            get: { militaryTime ? String(format: "%02d", shownHour) : String(shownHour) },
            set: { text in
                hourTyped = String(text.filter(\.isNumber).suffix(2))
                if let hour = Self.clockValue(text, in: hourRange) { setHour(hour) }
            }
        )
    }

    private var isPM: Binding<Bool> {
        Binding(
            get: { hour24 >= 12 },
            set: { pm in hour24 = hour24 % 12 + (pm ? 12 : 0) }
        )
    }

    /// The minutes box's text, using the same digital-clock typing as the hour box but
    /// keeping exactly what was typed ("0", "07", or empty) until the box loses focus.
    private var minuteBinding: Binding<String> {
        Binding(
            get: { minuteText },
            set: { text in
                let digits = text.filter(\.isNumber)
                if digits.isEmpty {
                    minuteText = ""
                } else if let two = Int(digits.suffix(2)), two <= 59 {
                    minuteText = String(digits.suffix(2))
                } else {
                    minuteText = String(digits.suffix(1))
                }
            }
        )
    }

    private func numberBox(_ text: Binding<String>) -> some View {
        TextField("", text: text)
            .bubbleNumberBoxStyle(width: 46, fontSize: 22)
            .onSubmit(save) // Return adds or saves it
    }

    /// The number typed into the hour box, or nil to keep the old one. Typing works like a digital
    /// clock: the last two digits typed win if they're in `range`, otherwise just the last one
    /// (so "12" then "3" is 3).
    private static func clockValue(_ text: String, in range: ClosedRange<Int>) -> Int? {
        let digits = text.filter(\.isNumber)
        if digits.isEmpty { return range.contains(0) ? 0 : nil }
        if let two = Int(digits.suffix(2)), range.contains(two) { return two }
        if let one = Int(digits.suffix(1)), range.contains(one) { return one }
        return nil
    }

    private func save() {
        let text = ReminderStore.cleanMessage(message)
        if let editing {
            store.update(editing.id, at: time, message: text)
        } else {
            store.add(at: time, message: text)
        }
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
                Text(AppPreferences.clockText(reminder.date))
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
