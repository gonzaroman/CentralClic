import AppKit
import ApplicationServices
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?
    private var sigterm: DispatchSourceSignal?
    private var systemStateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "Magic Middle Click")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        let settings = AppSettings.shared
        Multitouch.shared.onDevicesChanged = { count in
            LiveTouches.shared.connectedMice = count
            // A freshly connected mouse starts with the macOS values: apply ours again.
            MouseTuning.shared.forgetApplied()
            AppSettings.shared.applyMotion()
        }

        if Multitouch.shared.load() {
            Multitouch.shared.rescan()
            Multitouch.shared.watchDevices()
        } else {
            let alert = NSAlert()
            alert.messageText = L("This Mac can’t read the Magic Mouse")
            alert.informativeText = L("The macOS MultitouchSupport component wasn’t found.")
            alert.runModal()
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Multitouch.shared.scheduleRescan(after: 2)
        }
        // If the scroll direction is changed in System Settings, recompute the mouse inversion.
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("SwipeScrollDirectionDidChangeNotification"), object: nil, queue: .main) { _ in
            AppSettings.shared.applyMotion()
        }
        // Quitting with `kill` (SIGTERM) also puts the macOS speeds back.
        signal(SIGTERM, SIG_IGN)
        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler { NSApp.terminate(nil) }
        sigterm.resume()
        self.sigterm = sigterm

        settings.applyMotion()
        startEventTap()

        Updater.shared.onNewVersion = { [weak self] release in self?.showUpdateAlert(release) }
        Updater.shared.start()
        Engagement.onMilestone = { [weak self] in self?.showSupportAlert() }

        if settings.consumeFirstLaunch() { showSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppSettings.shared.restoreSystemMotion()
        Multitouch.shared.stopAll()
    }

    // MARK: Accessibility permission

    private func startEventTap() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        LiveTouches.shared.accessibilityGranted = trusted
        if trusted && EventTap.shared.start() { return }

        // Wait for the user to grant the permission, then start without restarting the app.
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            let granted = AXIsProcessTrusted()
            LiveTouches.shared.accessibilityGranted = granted
            if granted && EventTap.shared.start() {
                timer.invalidate()
                self?.permissionTimer = nil
            }
        }
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let settings = AppSettings.shared
        let live = LiveTouches.shared

        if let release = Updater.shared.available {
            menu.addItem(item(L("Update Available: %@…", release.version), #selector(downloadUpdate)))
            menu.addItem(.separator())
        }

        let mouse = NSMenuItem(title: live.connectedMice > 0 ? L("Magic Mouse connected") : L("Magic Mouse not detected"),
                               action: nil, keyEquivalent: "")
        mouse.isEnabled = false
        menu.addItem(mouse)
        if !live.accessibilityGranted {
            menu.addItem(item(L("Grant Accessibility Permission…"), #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        let enabled = item(L("Enabled"), #selector(toggleEnabled))
        enabled.state = settings.enabled ? .on : .off
        menu.addItem(enabled)
        menu.addItem(.separator())

        menu.addItem(item(L("Settings…"), #selector(showSettings), key: ","))
        let login = item(L("Open at Login"), #selector(toggleLaunchAtLogin))
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        menu.addItem(item(L("Check for Updates…"), #selector(checkForUpdates)))
        menu.addItem(.separator())

        menu.addItem(item(L("Star on GitHub…"), #selector(starOnGitHub)))
        menu.addItem(item(L("Share Magic Middle Click…"), #selector(shareApp)))
        menu.addItem(.separator())
        menu.addItem(item(L("Quit Magic Middle Click"), #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func toggleEnabled() {
        AppSettings.shared.enabled.toggle()
        statusItem.button?.appearsDisabled = !AppSettings.shared.enabled
    }

    @objc private func toggleLaunchAtLogin() {
        AppSettings.shared.setLaunchAtLogin(!AppSettings.shared.launchAtLogin)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Updates

    @objc private func checkForUpdates() {
        Updater.shared.check { [weak self] outcome in
            switch outcome {
            case .newer(let release):
                self?.showUpdateAlert(release)
            case .upToDate:
                let alert = NSAlert()
                alert.messageText = L("You’re up to date")
                alert.informativeText = L("Magic Middle Click %@ is the latest version.", Updater.shared.currentVersion)
                alert.addButton(withTitle: L("OK"))
                self?.runFrontmost(alert)
            case .failed:
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = L("Couldn’t check for updates")
                alert.informativeText = L("Check your internet connection and try again.")
                alert.addButton(withTitle: L("OK"))
                self?.runFrontmost(alert)
            }
        }
    }

    @objc private func downloadUpdate() { Updater.shared.openDownload() }

    private func showUpdateAlert(_ release: Updater.Release) {
        let alert = NSAlert()
        alert.messageText = L("A new version of Magic Middle Click is available")
        alert.informativeText = L("Version %@ is available (you have %@).", release.version, Updater.shared.currentVersion)
        alert.addButton(withTitle: L("Download"))
        alert.addButton(withTitle: L("Later"))
        if runFrontmost(alert) == .alertFirstButtonReturn { Updater.shared.openDownload() }
    }

    // MARK: Support the project

    @objc private func starOnGitHub() { Project.openRepository() }

    @objc private func shareApp() {
        guard let button = statusItem.button else { return }
        let picker = NSSharingServicePicker(items: [Project.shareMessage, Project.url])
        picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    /// Shown only once, after the app has made `Engagement.milestone` middle clicks.
    private func showSupportAlert() {
        let alert = NSAlert()
        alert.messageText = L("Magic Middle Click has made %ld middle clicks for you!", Engagement.milestone)
        alert.informativeText = L("If it’s useful to you, a star on GitHub or sharing it with a friend helps a lot. This message won’t appear again.")
        alert.addButton(withTitle: L("Star on GitHub"))
        alert.addButton(withTitle: L("Share…"))
        alert.addButton(withTitle: L("Not Now"))
        switch runFrontmost(alert) {
        case .alertFirstButtonReturn: Project.openRepository()
        case .alertSecondButtonReturn: shareApp()
        default: break
        }
    }

    /// This is a menu bar app: bring it to the front so the alert isn't hidden behind other windows.
    @discardableResult
    private func runFrontmost(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    // MARK: Settings window

    @objc func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(openAccessibility: { [weak self] in self?.openAccessibilitySettings() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Magic Middle Click"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        GestureEngine.shared.setLive(true)
        // While the window is open, follow changes made in System Settings (pointer acceleration).
        AppSettings.shared.refreshSystemState()
        systemStateTimer?.invalidate()
        systemStateTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            AppSettings.shared.refreshSystemState()
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        GestureEngine.shared.setLive(false)
        LiveTouches.shared.points = []
        systemStateTimer?.invalidate()
        systemStateTimer = nil
    }
}
