import SwiftUI

@main
struct DesktopPetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Desktop Pet", systemImage: "cat.fill") {
            MenuContent(controller: AppController.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppController.shared.start()
    }
}

struct MenuContent: View {
    let controller: AppController

    var body: some View {
        Button(controller.isPetVisible ? "Hide Pet" : "Show Pet") {
            controller.togglePet()
        }
        .keyboardShortcut("p")

        Divider()

        if !controller.timer.isBusy { // stop the current timer first
            Menu("Start Timer") {
                ForEach(PetTimer.presetMinutes, id: \.self) { minutes in
                    Button(AppController.presetTitle(minutes)) {
                        controller.startTimer(minutes: minutes)
                    }
                }
                Divider()
                Button("Custom…") {
                    controller.showSetTimerWindow()
                }
            }

            Button(controller.startPomodoroTitle) {
                controller.startPomodoro()
            }

            Button("Start Stopwatch") {
                controller.timer.startStopwatch()
            }
        }

        if let title = controller.timer.nextPomodoroPeriodTitle {
            Button(title) {
                controller.timer.startNextPomodoroPeriod()
            }
        }

        if controller.timer.hasCountdown {
            Button(controller.timer.pauseTitle) {
                controller.timer.togglePause()
            }
        }

        if controller.timer.hasCountdown && !controller.timer.isStopwatch {
            Menu("Edit Timer") {
                ForEach(AppController.editMenuSteps, id: \.self) { step in
                    Button(PetTimer.editTitle(step)) {
                        controller.timer.adjust(bySeconds: step)
                    }
                    .disabled(!controller.timer.canAdjust(bySeconds: step))
                }
            }
        }

        if controller.timer.isActive {
            Button(controller.timer.stopTitle) {
                controller.timer.stop()
            }
        }

        Divider()

        Button("Reminders…") {
            controller.showRemindersWindow()
        }

        Button("Customize…") {
            controller.showCustomizeWindow()
        }
        .keyboardShortcut(",")

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { controller.launchesAtLogin },
            set: { controller.setLaunchesAtLogin($0) }
        ))

        Divider()

        Button("Quit Desktop Pet") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
