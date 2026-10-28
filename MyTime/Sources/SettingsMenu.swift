import AppKit

/// The pet's only chrome: a menu on the gear (and on right-click).
final class SettingsMenu: NSObject, NSMenuDelegate {

    let menu = NSMenu()
    var onOpenChanged: ((Bool) -> Void)?

    private let onChange: () -> Void
    private var systemZoneItem: NSMenuItem?
    private var use24HourItem: NSMenuItem?
    private var secondsItem: NSMenuItem?
    private var dateItem: NSMenuItem?
    /// NSMenu holds its delegate weakly, so we own the region delegates here.
    private var regions: [RegionMenu] = []

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        build()
    }

    // MARK: - Building

    private func build() {
        let zoneItem = NSMenuItem(title: "Time Zone", action: nil, keyEquivalent: "")
        zoneItem.submenu = buildZoneMenu()
        menu.addItem(zoneItem)
        menu.addItem(.separator())

        use24HourItem = addItem(title: "24-Hour Time", action: #selector(toggle24Hour))
        secondsItem = addItem(title: "Show Seconds", action: #selector(toggleSeconds))
        dateItem = addItem(title: "Show Date", action: #selector(toggleDate))
        menu.addItem(.separator())
        addItem(title: "Quit MyTime", action: #selector(quit), key: "q")
    }

    @discardableResult
    private func addItem(title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    private func buildZoneMenu() -> NSMenu {
        let zoneMenu = NSMenu()
        zoneMenu.autoenablesItems = false

        let system = NSMenuItem(title: "Follow System",
                                action: #selector(useSystemZone),
                                keyEquivalent: "")
        system.target = self
        zoneMenu.addItem(system)
        systemZoneItem = system
        zoneMenu.addItem(.separator())

        // Group the ~400 IANA identifiers by their region prefix. Only the
        // headings are created now; the cities inside each one are built the
        // first time that submenu is actually opened.
        var byRegion: [String: [String]] = [:]
        for id in TimeZone.knownTimeZoneIdentifiers {
            let region = id.contains("/") ? String(id.split(separator: "/")[0]) : "Other"
            byRegion[region, default: []].append(id)
        }

        for region in byRegion.keys.sorted() {
            let item = NSMenuItem(title: region.replacingOccurrences(of: "_", with: " "),
                                  action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            let delegate = RegionMenu(ids: byRegion[region]!.sorted(), owner: self)
            submenu.delegate = delegate
            regions.append(delegate)
            item.submenu = submenu
            zoneMenu.addItem(item)
        }
        return zoneMenu
    }

    // MARK: - Presenting

    func popUp(under button: NSButton, in view: NSView) {
        menu.popUp(positioning: nil,
                   at: NSPoint(x: button.frame.minX - 6, y: button.frame.minY - 4),
                   in: view)
    }

    // Only the root menu has us as its delegate, so these fire once per opening.
    func menuWillOpen(_ menu: NSMenu) { onOpenChanged?(true) }
    func menuDidClose(_ menu: NSMenu) { onOpenChanged?(false) }

    func menuNeedsUpdate(_ menu: NSMenu) {
        systemZoneItem?.state = Prefs.followsSystemZone ? .on : .off
        use24HourItem?.state = Prefs.use24Hour ? .on : .off
        secondsItem?.state = Prefs.showSeconds ? .on : .off
        dateItem?.state = Prefs.showDate ? .on : .off
    }

    // MARK: - Actions

    fileprivate func select(zoneID: String) {
        Prefs.zoneID = zoneID
        onChange()
    }

    @objc private func useSystemZone() {
        Prefs.followSystemZone()
        onChange()
    }

    @objc private func toggle24Hour() {
        Prefs.use24Hour.toggle()
        onChange()
    }

    @objc private func toggleSeconds() {
        Prefs.showSeconds.toggle()
        onChange()
    }

    @objc private func toggleDate() {
        Prefs.showDate.toggle()
        onChange()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Fills one region's city list on demand, so a user who never opens
/// "Antarctica" never pays for its menu items.
private final class RegionMenu: NSObject, NSMenuDelegate {
    private let ids: [String]
    private weak var owner: SettingsMenu?

    init(ids: [String], owner: SettingsMenu) {
        self.ids = ids
        self.owner = owner
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.numberOfItems == 0 {
            for id in ids {
                let city = id.contains("/")
                    ? id.split(separator: "/").dropFirst().joined(separator: " / ")
                    : id
                let item = NSMenuItem(title: city.replacingOccurrences(of: "_", with: " "),
                                      action: #selector(pick(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.representedObject = id
                menu.addItem(item)
            }
        }
        // A checkmark only means "explicitly chosen"; following the system is
        // shown on the Follow System item instead.
        let current = Prefs.followsSystemZone ? nil : Prefs.zoneID
        for item in menu.items {
            item.state = (item.representedObject as? String) == current ? .on : .off
        }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        owner?.select(zoneID: id)
    }
}
