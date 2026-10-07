import SwiftUI

/// App-wide preferences that aren't about how the pet looks.
enum AppPreferences {
    /// Show and type times on a 24-hour clock ("14:30") instead of with AM/PM.
    static let militaryTimeKey = "settings.militaryTime"

    static var usesMilitaryTime: Bool { UserDefaults.standard.bool(forKey: militaryTimeKey) }

    /// How many minutes before a Google Calendar meeting its reminder goes off (0 = when it starts).
    /// Only meetings: a reminder you set for 3:00 yourself still goes off at 3:00.
    static let meetingLeadKey = "settings.meetingLeadMinutes"
    /// Up to 3 hours, for leaving early to get somewhere.
    static let meetingLeadRange = 0...180

    static var meetingLeadMinutes: Int { UserDefaults.standard.integer(forKey: meetingLeadKey) }

    /// Topsy greets you once a day with your to-dos and meetings. On unless turned off.
    static let morningGreetingKey = "settings.morningGreeting"

    static var showsMorningGreeting: Bool {
        UserDefaults.standard.object(forKey: morningGreetingKey) as? Bool ?? true
    }

    /// "2:30 PM", or "14:30" with military time on.
    static func clockText(_ date: Date) -> String {
        guard usesMilitaryTime else { return date.formatted(date: .omitted, time: .shortened) }
        // Built by hand: `.hour(.twoDigits(amPM: .omitted))` still gives 12-hour hours ("02:30" for 14:30)
        // when the Mac is set to a 12-hour clock.
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// The bubble's "Settings" page.
struct BubbleSettingsPage: View {
    /// Meeting reminders move as soon as the lead time changes.
    let reminders: ReminderStore
    @AppStorage(AppPreferences.militaryTimeKey) private var militaryTime = false
    @AppStorage(AppPreferences.meetingLeadKey) private var meetingLead = 0
    @AppStorage(AppPreferences.morningGreetingKey) private var morningGreeting = true
    /// Kept unfocused on open (like Customize's name), so a stray keypress can't change the minutes.
    @FocusState private var leadFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            Toggle(isOn: $militaryTime) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Military time")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(militaryTime ? "Times look like 14:30" : "Times look like 2:30 PM")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(BubbleSwitchStyle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))

            Toggle(isOn: $morningGreeting) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Morning greeting")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text("Your to-dos and meetings")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(BubbleSwitchStyle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 5) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        // The same calendar mark as meeting rows on the Reminders page.
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .bold))
                            .opacity(0.55)
                        Text("Meeting reminders")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    Text("Google Calendar meetings only")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
                HStack(spacing: 6) {
                    TextField("", text: TimerDraft.digits($meetingLead, in: AppPreferences.meetingLeadRange))
                        .bubbleNumberBoxStyle(width: 52, fontSize: 18)
                        .focused($leadFocused)
                    CaretStepper(
                        canIncrement: meetingLead < AppPreferences.meetingLeadRange.upperBound,
                        canDecrement: meetingLead > AppPreferences.meetingLeadRange.lowerBound,
                        increment: { meetingLead += 1 },
                        decrement: { meetingLead -= 1 }
                    )
                    Text("min before")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
                .frame(maxWidth: .infinity) // centered in the box
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
            // Waits for typing or holding a caret to settle, so a meeting doesn't come due
            // (and make Topsy hop) at an in-between number like the 1 of "15".
            .onAppear {
                DispatchQueue.main.async { leadFocused = false }
            }
            .task(id: meetingLead) {
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled { reminders.applyMeetingLead() }
            }
        }
    }
}

/// An on/off switch drawn like the bubble: black outline, filled black when on.
struct BubbleSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? Color.black : .white)
                    .overlay(Capsule().stroke(.black, lineWidth: 1.5))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .overlay(Circle().stroke(.black, lineWidth: 1.5))
                            .frame(width: 14, height: 14)
                            .padding(3)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
