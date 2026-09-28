import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// Owns the floating pet window and the Customize window.
@Observable
final class AppController {
    static let shared = AppController()

    let settings = PetSettings()
    private(set) var isPetVisible = false
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var petPanel: PetPanel?
    @ObservationIgnored private var customizeWindow: NSWindow?

    private static let visibleKey = "petVisible"

    private init() {
        settings.onChange = { [weak self] in self?.refreshPetImage() }
    }

    func start() {
        let panel = PetPanel(image: PetRenderer.render(settings.palette))
        panel.onHide = { [weak self] in self?.setPetVisible(false) }
        panel.onCustomize = { [weak self] in self?.showCustomizeWindow() }
        petPanel = panel

        let wasVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
        setPetVisible(wasVisible)
    }

    func togglePet() {
        setPetVisible(!isPetVisible)
    }

    func setPetVisible(_ visible: Bool) {
        isPetVisible = visible
        UserDefaults.standard.set(visible, forKey: Self.visibleKey)
        if visible {
            petPanel?.orderFrontRegardless()
        } else {
            petPanel?.orderOut(nil)
        }
    }

    func showCustomizeWindow() {
        if customizeWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: CustomizeView(settings: settings)
            ))
            window.title = "Customize Pet"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            customizeWindow = window
        }
        NSApp.activate()
        customizeWindow?.makeKeyAndOrderFront(nil)
    }

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at Login change failed: \(error)")
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func refreshPetImage() {
        petPanel?.setImage(PetRenderer.render(settings.palette))
    }
}
