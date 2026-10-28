import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var panel: PetPanel!
    private var view: PetView!
    private var clock: Clock!
    private var settings: SettingsMenu!
    private var pendingSave: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        installMainMenu()

        view = PetView()

        settings = SettingsMenu { [weak self] in self?.refresh() }
        settings.onOpenChanged = { [weak self] open in self?.view.setMenuOpen(open) }
        view.menu = settings.menu                     // right-click anywhere on the pet
        view.onGear = { [weak self] button in
            guard let self = self else { return }
            self.settings.popUp(under: button, in: self.view)
        }

        panel = PetPanel(content: view)
        view.onSizeChange = { [weak self] size in self?.resize(to: size) }
        panel.delegate = self
        panel.setFrameOrigin(startingOrigin())
        panel.orderFrontRegardless()                  // show without activating the app

        clock = Clock(onTime: { [weak self] text in self?.view.setTime(text) },
                      onDate: { [weak self] badge in self?.view.setDate(badge) })
        refresh()
        observeSystemChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Catch a quit that lands inside the save debounce window.
        pendingSave?.cancel()
        Prefs.origin = panel.frame.origin
    }

    /// Re-read every preference and rebuild what depends on it.
    private func refresh() {
        let zone = Prefs.timeZone
        let short = zone.abbreviation(for: Date())
            ?? zone.identifier.components(separatedBy: "/").last
            ?? zone.identifier
        view.setZone(label: short,
                     tooltip: Prefs.followsSystemZone
                        ? "\(zone.identifier) (following system)"
                        : zone.identifier)
        clock.rebuild()
    }

    // MARK: - Placement

    private func startingOrigin() -> CGPoint {
        if let saved = Prefs.origin { return clamped(saved) }
        guard let screen = preferredScreen()?.visibleFrame else { return .zero }
        return CGPoint(x: screen.maxX - cardSize.width - 16, y: screen.minY + 16)
    }

    /// The card grows and shrinks with the date tile. It grows leftwards - the
    /// pet's usual home is the bottom-right corner, and keeping the right edge
    /// put means the time does not jump when the date is switched on.
    private func resize(to size: NSSize) {
        guard let panel = panel else { return }
        let right = panel.frame.maxX
        panel.setFrame(NSRect(x: right - size.width, y: panel.frame.minY,
                              width: size.width, height: size.height),
                       display: true)
        panel.setFrameOrigin(clamped(panel.frame.origin))
    }

    private var cardSize: NSSize { view?.frame.size ?? PetView.baseSize }

    /// The display the pointer is on. `NSScreen.main` means "screen with the key
    /// window", which at launch is whatever was focused last - on a multi-display
    /// Mac that can drop the pet on a screen the user isn't even looking at.
    private func preferredScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Keeps the pet on a screen that actually exists - important when it was
    /// last parked on a display that is no longer plugged in.
    private func clamped(_ origin: CGPoint) -> CGPoint {
        let size = cardSize
        let center = CGPoint(x: origin.x + size.width / 2, y: origin.y + size.height / 2)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return origin }
        return CGPoint(
            x: min(max(origin.x, frame.minX), max(frame.maxX - size.width, frame.minX)),
            y: min(max(origin.y, frame.minY), max(frame.maxY - size.height, frame.minY)))
    }

    func windowDidMove(_ notification: Notification) {
        // This fires continuously during a drag; write once the pet settles.
        pendingSave?.cancel()
        let origin = panel.frame.origin
        let work = DispatchWorkItem { Prefs.origin = origin }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - System changes

    private func observeSystemChanges() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSNotification.Name.NSSystemClockDidChange,
                           object: nil, queue: .main) { [weak self] _ in
            self?.clock.restart()
        }
        center.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange,
                           object: nil, queue: .main) { [weak self] _ in
            self?.refresh()                            // matters when following the system zone
        }
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                           object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.panel.setFrameOrigin(self.clamped(self.panel.frame.origin))
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            self?.clock.restart()                      // the clock is stale after sleep
        }
        // Nothing to redraw while the screens are off.
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                              object: nil, queue: .main) { [weak self] _ in
            self?.clock.stop()
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            self?.clock.restart()
        }
    }

    /// There is no Dock icon, so this exists only to give Cmd-Q something to hit.
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MyTime",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)     // desktop pet: no Dock icon, no app switcher
let delegate = AppDelegate()
app.delegate = delegate
app.run()
