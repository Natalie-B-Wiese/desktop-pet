import AppKit
import SwiftUI

/// App-wide preferences that aren't about how the pet looks.
enum AppPreferences {
    /// Show and type times on a 24-hour clock ("14:30") instead of with AM/PM.
    static let militaryTimeKey = "settings.militaryTime"

    static var usesMilitaryTime: Bool { UserDefaults.standard.bool(forKey: militaryTimeKey) }

    /// How many minutes before every reminder (your own and meetings) Topsy hops with a heads-up (0 = none).
    /// The reminder itself still comes due at its time; a meeting's at its start.
    static let headsUpKey = "settings.headsUpMinutes"
    /// Up to 3 hours, for leaving early to get somewhere.
    static let headsUpRange = 0...180
    static let defaultHeadsUpMinutes = 5

    static var headsUpMinutes: Int {
        UserDefaults.standard.object(forKey: headsUpKey) as? Int ?? defaultHeadsUpMinutes
    }

    /// The old "Meeting reminders" setting (meetings went off this early) becomes the heads-up for all reminders.
    static func moveMeetingLeadToHeadsUp() {
        let defaults = UserDefaults.standard
        let oldKey = "settings.meetingLeadMinutes"
        guard let old = defaults.object(forKey: oldKey) as? Int else { return }
        if defaults.object(forKey: headsUpKey) == nil { defaults.set(old, forKey: headsUpKey) }
        defaults.removeObject(forKey: oldKey)
    }

    /// Topsy greets you once a day with your to-dos and meetings. On unless turned off.
    static let morningGreetingKey = "settings.morningGreeting"

    static var showsMorningGreeting: Bool {
        UserDefaults.standard.object(forKey: morningGreetingKey) as? Bool ?? true
    }

    /// Topsy's little comments (the greeting in her voice, lunch, to-dos and reminder heads-ups)
    /// in a personality's voice, or nil for None (the default), which keeps her quiet.
    static let chatterKey = "settings.chatter"
    /// None first, then the personalities, in the Settings picker's order.
    static let chatterChoices: [Personality?] = [nil, .sassy, .bubbly, .boss]

    static var chatter: Personality? {
        UserDefaults.standard.string(forKey: chatterKey).flatMap(Personality.init)
    }

    /// The sound Topsy makes whenever she hops (time's up, a reminder, the morning greeting).
    static let hopSoundKey = "settings.hopSound"
    /// Silent first, then macOS's built-in alert sounds, played by name.
    static let hopSounds = ["Silent", "Purr", "Ping", "Hero"]
    static let defaultHopSound = "Purr"

    /// A saved sound that's since been removed from the list falls back to the default.
    static var hopSound: String { validHopSound(UserDefaults.standard.string(forKey: hopSoundKey)) }

    static func validHopSound(_ name: String?) -> String {
        guard let name, hopSounds.contains(name) else { return defaultHopSound }
        return name
    }

    /// Plays `name` (the chosen hop sound by default) from the start. Silent plays nothing.
    static func playHopSound(_ name: String = hopSound) {
        guard name != "Silent", let sound = NSSound(named: name) else { return }
        sound.stop() // a shared instance: restart it if it's still playing
        sound.play()
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
    @AppStorage(AppPreferences.headsUpKey) private var headsUp = AppPreferences.defaultHeadsUpMinutes
    @AppStorage(AppPreferences.morningGreetingKey) private var morningGreeting = true
    @AppStorage(AppPreferences.chatterKey) private var chatter = "none"
    /// Called after picking a Chatter personality, so she says a line in her new voice.
    var onChatterChange: (Personality?) -> Void = { _ in }
    @AppStorage(AppPreferences.hopSoundKey) private var hopSound = AppPreferences.defaultHopSound
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

            chatterPicker

            hopSoundPicker

            VStack(alignment: .leading, spacing: 5) {
                Text("Reminders")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                HStack(spacing: 6) {
                    TextField("", text: TimerDraft.digits($headsUp, in: AppPreferences.headsUpRange))
                        .bubbleNumberBoxStyle(width: 52, fontSize: 18)
                        .focused($leadFocused)
                    CaretStepper(
                        canIncrement: headsUp < AppPreferences.headsUpRange.upperBound,
                        canDecrement: headsUp > AppPreferences.headsUpRange.lowerBound,
                        increment: { headsUp += 1 },
                        decrement: { headsUp -= 1 }
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
            // Waits for typing or holding a caret to settle, so a heads-up doesn't pop up
            // (and make Topsy hop) at an in-between number like the 1 of "15".
            .onAppear {
                DispatchQueue.main.async { leadFocused = false }
            }
            .task(id: headsUp) {
                try? await Task.sleep(for: .milliseconds(600))
                if !Task.isCancelled { reminders.applyHeadsUpChange() }
            }
        }
    }
}

extension BubbleSettingsPage {
    /// "Notification 🔊  ‹ Purr ›": the arrows step through the sounds like Customize's steppers
    /// (wrapping around) and play each one; the speaker plays the current one again.
    private var hopSoundPicker: some View {
        let sound = AppPreferences.validHopSound(hopSound)
        return HStack(spacing: 0) {
            Text("Notification")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
            HeaderIconButton(
                systemImage: sound == "Silent" ? "speaker.slash.fill" : "speaker.wave.2.fill",
                help: "Play sound",
                width: 22
            ) { AppPreferences.playHopSound(sound) }
            .disabled(sound == "Silent")
            .opacity(sound == "Silent" ? 0.35 : 0.7)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                HeaderIconButton(systemImage: "chevron.left", help: "Previous sound", width: 18) { stepHopSound(-1) }
                Text(sound)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 44)
                HeaderIconButton(systemImage: "chevron.right", help: "Next sound", width: 18) { stepHopSound(1) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }

    /// "Chatter  ‹ Sassy ›", like the Notification row.
    private var chatterPicker: some View {
        HStack(spacing: 0) {
            Text("Chatter")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                HeaderIconButton(systemImage: "chevron.left", help: "Previous personality", width: 18) { stepChatter(-1) }
                Text(Personality(rawValue: chatter)?.title ?? "None")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 52)
                HeaderIconButton(systemImage: "chevron.right", help: "Next personality", width: 18) { stepChatter(1) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }

    private func stepChatter(_ step: Int) {
        let choices = AppPreferences.chatterChoices
        let index = choices.firstIndex(of: Personality(rawValue: chatter)) ?? 0
        let next = choices[(index + step + choices.count) % choices.count]
        chatter = next?.rawValue ?? "none"
        onChatterChange(next)
    }

    private func stepHopSound(_ step: Int) {
        let sounds = AppPreferences.hopSounds
        let index = sounds.firstIndex(of: AppPreferences.validHopSound(hopSound)) ?? 0
        hopSound = sounds[(index + step + sounds.count) % sounds.count]
        AppPreferences.playHopSound(hopSound)
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
