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

        if controller.timer.isActive {
            Button("Stop Timer") {
                controller.timer.stop()
            }
        }

        Divider()

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
