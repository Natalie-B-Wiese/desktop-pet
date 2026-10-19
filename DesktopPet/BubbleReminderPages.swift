import SwiftUI

/// The bubble's "Reminders" page: every upcoming reminder (click one to edit it), Add, and Pull meetings.
struct BubbleRemindersPage: View {
    let store: ReminderStore
    var onAdd: () -> Void
    var onEdit: (Reminder.ID) -> Void

    /// What the last pull did, like "Added 2 meetings".
    @State private var pullStatus: String?
    @State private var isPulling = false
    @State private var needsCalendarAccess = false

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
            BubbleButton(isPulling ? "Pulling…" : "Pull meetings", systemImage: "calendar.badge.plus", action: pullMeetings)
                .disabled(isPulling)

            if let pullStatus {
                Text(pullStatus)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.55)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if needsCalendarAccess {
                BubbleButton("Open Settings", systemImage: "gearshape", style: .quiet, action: CalendarMeetings.openPrivacySettings)
            }
        }
    }

    /// Adds a reminder for each of today's remaining meetings from the Calendar app (which syncs Google Calendar).
    private func pullMeetings() {
        isPulling = true
        Task { @MainActor in
            defer { isPulling = false }
            do {
                let meetings = try await CalendarMeetings.todaysUpcoming()
                let result = store.syncMeetings(meetings)
                needsCalendarAccess = false
                pullStatus = Self.statusText(found: meetings.count, added: result.added, changed: result.changed)
            } catch CalendarMeetings.PullError.noAccess {
                needsCalendarAccess = true
                pullStatus = "Topsy can't see your calendar. Turn on Desktop Pet under Calendars."
            } catch {
                pullStatus = "Couldn't read your calendar."
            }
        }
    }

    private static func statusText(found: Int, added: Int, changed: Int) -> String {
        if found == 0 && added == 0 && changed == 0 { return "No more meetings today" }
        var parts: [String] = []
        if added > 0 { parts.append("Added \(added) meeting\(added == 1 ? "" : "s")") }
        if changed > 0 { parts.append("updated \(changed)") }
        if parts.isEmpty { return "Meetings are up to date" }
        return parts.joined(separator: ", ")
    }

    private func rowText(_ reminder: Reminder) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // A repeating one shows just the clock time; the line below says which days.
                Text(reminder.repeats ? AppPreferences.clockText(reminder.shownDate) : ReminderStore.timeText(reminder.shownDate))
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                if reminder.meetingID != nil {
                    Image(systemName: "calendar")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.55)
                }
            }
            if let days = reminder.repeatDays, !days.isEmpty {
                Label(ReminderStore.repeatText(days), systemImage: "repeat")
                    .labelStyle(RepeatLabelStyle())
                    .opacity(0.55)
                    .lineLimit(1)
            }
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

    private func rows(_ reminders: [Reminder]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(reminders) { reminder in
                row(reminder)
            }
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        HStack(spacing: 6) {
            if reminder.meetingID != nil {
                // Synced from the calendar, so it can't be edited here; change the meeting instead.
                rowText(reminder)
                    .help("From your calendar")
            } else {
                Button {
                    onEdit(reminder.id)
                } label: {
                    rowText(reminder)
                }
                .buttonStyle(.plain)
                .help("Edit reminder")
            }

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
    /// The hour box's text as typed, like `minuteText`; tidied (e.g. "2" → "02" in military) when it loses focus.
    @State private var hourText: String
    /// The minutes as typed, so the box can be empty while editing; padded to "05" when it loses focus.
    @State private var minuteText: String
    @State private var message: String
    /// The weekdays it repeats on (1 = Sunday … 7 = Saturday); empty means once.
    @State private var repeatDays: Set<Int>
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
        _hourText = State(initialValue: Self.hourText(for: start.hour ?? 12, military: AppPreferences.usesMilitaryTime))
        _minuteText = State(initialValue: String(format: "%02d", start.minute ?? 0))
        _message = State(initialValue: editing?.message ?? "")
        _repeatDays = State(initialValue: editing?.repeatDays ?? [])
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
                    Text(":")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .offset(y: -2) // sits a touch high, like a clock's colon
                    // Backspace in an empty minutes box goes back to the hour box, selected, so typing replaces it.
                    numberBox(minuteBinding)
                        .focused($focusedField, equals: .minute)
                        // The Delete key arrives as U+007F, which `.onKeyPress(.delete)` doesn't match.
                        .onKeyPress(characters: CharacterSet(charactersIn: "\u{7F}\u{8}")) { _ in
                            guard minuteText.isEmpty else { return .ignored }
                            focusedField = .hour
                            return .handled
                        }
                        // Space and ":" mean nothing in the minutes, so they're ignored instead of clearing the box.
                        .onKeyPress(characters: CharacterSet(charactersIn: " :")) { _ in .handled }
                    if !militaryTime {
                        BubbleTabs(selection: isPM, options: [(false, "AM"), (true, "PM")], vertical: true)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.leading, 6)
                    }
                }
                .fixedSize(horizontal: false, vertical: true) // AM/PM matches the boxes' height

                // "Today · Noon": says roughly when it is, since 12 PM is easy to mistake for midnight.
                Text("\(ReminderStore.dayWord(for: time, repeatDays: repeatDays)) · \(ReminderStore.partOfDay(hour24: hour24))")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.55)
            }

            dayCircles

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
        .onChange(of: focusedField) { old, _ in
            if old == .minute { minuteText = String(format: "%02d", minute) }
            if old == .hour { hourText = Self.hourText(for: hour24, military: militaryTime) }
        }
        .onExitCommand(perform: onClose) // Esc closes the menu
    }

    /// One circle per weekday, in the week order of this Mac. Picking none makes it a one-time reminder.
    private var dayCircles: some View {
        let letters = Calendar.current.veryShortWeekdaySymbols
        let names = Calendar.current.weekdaySymbols
        return HStack(spacing: 3) {
            ForEach(ReminderStore.orderedWeekdays, id: \.self) { weekday in
                let on = repeatDays.contains(weekday)
                Button {
                    if on { repeatDays.remove(weekday) } else { repeatDays.insert(weekday) }
                } label: {
                    Text(letters[weekday - 1])
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(on ? Color.white : .black)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(on ? Color.black : .white))
                        .overlay(Circle().stroke(.black, lineWidth: 1.5))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(on ? "Stop repeating on \(names[weekday - 1])" : "Repeat every \(names[weekday - 1])")
            }
        }
    }

    private var hourRange: ClosedRange<Int> { militaryTime ? 0...23 : 1...12 }

    /// How the hour box shows an hour when you're not typing in it: "09" with military time, "9" with AM/PM.
    private static func hourText(for hour24: Int, military: Bool) -> String {
        military ? String(format: "%02d", hour24) : String(hour24 % 12 == 0 ? 12 : hour24 % 12)
    }

    /// Sets the hour as shown in the box (0…23, or 1…12 keeping AM/PM).
    private func setHour(_ hour: Int) {
        hour24 = militaryTime ? hour : hour % 12 + (hour24 >= 12 ? 12 : 0)
    }

    /// The hour box's text: 00…23 with military time, otherwise 1…12 (AM/PM is picked separately).
    private var hourBinding: Binding<String> {
        // Like the minutes: keeps exactly what was typed ("2", "05", "0", or empty), so the text
        // never changes under the cursor. Selecting the hour and typing replaces it.
        Binding(
            get: { hourText },
            set: { text in
                let digits = text.filter(\.isNumber)
                if let two = Int(digits.suffix(2)), digits.count >= 2, hourRange.contains(two) {
                    hourText = String(digits.suffix(2))
                    setHour(two)
                } else if let one = Int(digits.suffix(1)) {
                    hourText = String(digits.suffix(1)) // a lone "0" is kept, since it can become "05"
                    if hourRange.contains(one) { setHour(one) }
                } else {
                    hourText = ""
                }
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

    private func save() {
        let text = ReminderStore.cleanMessage(message)
        if let editing {
            store.update(editing.id, at: time, repeatDays: repeatDays, message: text)
        } else {
            store.add(at: time, repeatDays: repeatDays, message: text)
        }
        onAdded()
    }
}

/// A small grey "↻ Weekdays" after a repeating reminder's time.
private struct RepeatLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon.font(.system(size: 8, weight: .bold))
            configuration.title.font(.system(size: 10, weight: .semibold, design: .rounded))
        }
    }
}

/// What the bubble shows when a reminder comes due.
struct BubbleReminderAlert: View {
    let reminder: Reminder
    /// How many more are waiting after this one: other due reminders, the greeting and a finished timer.
    let moreCount: Int

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(AppPreferences.clockText(reminder.shownDate))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            }
            // Wraps at 180pt. The bubble measures itself with no width limit, which made a plain
            // `.frame(maxWidth:)` report one line's height for a wrapped message ("Click to close" spilled out).
            WrappingWidth(maxWidth: 180) {
                Text(reminder.message ?? "Reminder!")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            Text(moreCount > 0 ? "Click to close · \(moreCount) more" : "Click to close")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }
}

/// Gives its content its natural width up to `maxWidth`, and the height it needs when wrapped at that width,
/// even when the parent offers no width (the bubble sizes itself to its content's ideal size).
private struct WrappingWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let width = min(content.sizeThatFits(.unspecified).width, proposal.width ?? maxWidth, maxWidth)
        return content.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
