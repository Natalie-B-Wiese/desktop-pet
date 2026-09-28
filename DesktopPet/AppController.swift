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
        settings.onScaleChange = { [weak self] in
            guard let self else { return }
            petPanel?.setScale(CGFloat(settings.scale))
        }
    }

    func start() {
        let panel = PetPanel(image: PetRenderer.render(settings.palette), scale: CGFloat(settings.scale))
        panel.onHide = { [weak self] in self?.setPetVisible(false) }
        panel.onCustomize = { [weak self] in self?.showCustomizeWindow() }
        petPanel = panel

        let wasVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
        setPetVisible(wasVisible)

        // `open DesktopPet.app --args --customize` opens the Customize window right away (handy for testing).
        // Add `--snapshot <path.png>` to also save a picture of that window (lets Claude check the layout).
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--customize") {
            showCustomizeWindow()
            if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
                let path = args[i + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.snapshotCustomizeWindow(to: URL(fileURLWithPath: path))
                }
            }
        }
    }

    private func snapshotCustomizeWindow(to url: URL) {
        guard let view = customizeWindow?.contentView?.superview, // include the title bar
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
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
