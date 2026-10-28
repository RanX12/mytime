import AppKit

/// A label that never eats a mouse click, so the whole card stays draggable.
private final class PassiveLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The date icon: a little calendar tile with the weekday over the month and
/// day, so a glance at the pet answers "what day is it" as well as "when".
private final class DateTile: NSView {

    enum Metric {
        static let size = NSSize(width: 34, height: 27)   // width is a minimum
        static let padding: CGFloat = 5
        static let corner: CGFloat = 6
    }

    private let weekdayLabel = PassiveLabel(labelWithString: "")
    private let monthDayLabel = PassiveLabel(labelWithString: "")

    /// The widest short weekday in this locale, so the tile does not resize
    /// itself every midnight. Locale changes need a relaunch, which is what
    /// the rest of the app assumes too.
    private static let weekdayWidth: CGFloat = {
        let symbols = DateFormatter().shortWeekdaySymbols ?? []
        let font = NSFont.systemFont(ofSize: 9, weight: .semibold)
        return symbols.reduce(0) { max($0, (($1) as NSString).size(withAttributes: [.font: font]).width) }
    }()

    init() {
        super.init(frame: NSRect(origin: .zero, size: Metric.size))

        wantsLayer = true
        layer?.cornerRadius = Metric.corner
        layer?.cornerCurve = .continuous

        weekdayLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        weekdayLabel.textColor = .secondaryLabelColor
        weekdayLabel.alignment = .center
        addSubview(weekdayLabel)

        monthDayLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        monthDayLabel.textColor = .labelColor
        monthDayLabel.alignment = .center
        addSubview(monthDayLabel)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // Part of the card's background as far as the mouse is concerned.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.07).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func set(_ badge: DateBadge) {
        weekdayLabel.stringValue = badge.weekday
        monthDayLabel.stringValue = badge.monthDay
        needsLayout = true
    }

    /// Sized to the widest reading it could ever hold, not to today's: every
    /// digit run is measured as "88" so 9/3 and 12/25 occupy the same tile.
    var fittingWidth: CGFloat {
        let font = monthDayLabel.font ?? .systemFont(ofSize: 11)
        let widest = monthDayLabel.stringValue
            .replacingOccurrences(of: "[0-9]+", with: "88", options: .regularExpression)
        let dateWidth = (widest as NSString).size(withAttributes: [.font: font]).width
        return max(Metric.size.width,
                   ceil(max(dateWidth, DateTile.weekdayWidth)) + 2 * Metric.padding)
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        monthDayLabel.frame = NSRect(x: 0, y: 2, width: width, height: 13)
        weekdayLabel.frame = NSRect(x: 0, y: bounds.height - 2 - 11, width: width, height: 11)
    }
}

/// The pet's face: the date tile and time on the left, zone on the right, and a
/// gear that fades in only while the mouse is over the card.
final class PetView: NSView {

    /// The card without its date tile. The live size is `frame.size`, which
    /// grows leftwards when the date is switched on.
    static let baseSize = NSSize(width: 170, height: 35)

    private enum Metric {
        static let inset: CGFloat = 10
        static let gap: CGFloat = 7
        static let tileInset: CGFloat = 8
        static let tileGap: CGFloat = 8
        static let gear: CGFloat = 22
        static let gearInset: CGFloat = 6
        static let minZoneWidth: CGFloat = 30
        static let fade: TimeInterval = 0.12
    }

    private let dateTile = DateTile()
    private let timeLabel = PassiveLabel(labelWithString: "--:--:--")
    private let zoneLabel = PassiveLabel(labelWithString: "")
    private let gearButton = NSButton()
    private var trackingArea: NSTrackingArea?

    private var hovering = false
    private var menuOpen = false
    private var controlsShown = false

    var onGear: ((NSButton) -> Void)?
    /// Fires when the card needs a different width; the panel owns the window.
    var onSizeChange: ((NSSize) -> Void)?

    // MARK: - Setup

    init() {
        super.init(frame: NSRect(origin: .zero, size: PetView.baseSize))

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1

        dateTile.isHidden = true            // until the clock hands us a date
        addSubview(dateTile)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timeLabel.textColor = .labelColor
        addSubview(timeLabel)

        zoneLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        zoneLabel.textColor = .secondaryLabelColor
        zoneLabel.lineBreakMode = .byTruncatingTail
        addSubview(zoneLabel)

        gearButton.bezelStyle = .regularSquare
        gearButton.isBordered = false
        gearButton.imagePosition = .imageOnly
        gearButton.image = NSImage(systemSymbolName: "gearshape.fill",
                                   accessibilityDescription: "Clock settings")
        gearButton.contentTintColor = .secondaryLabelColor
        gearButton.target = self
        gearButton.action = #selector(gearTapped)
        gearButton.alphaValue = 0
        gearButton.isHidden = true          // hidden, so it cannot be clicked while invisible
        gearButton.toolTip = "Clock settings"
        addSubview(gearButton)

        layoutContents()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Appearance

    override func updateLayer() {
        // Layer colours are raw CGColors and do not follow light/dark on their
        // own, so resolve them against the appearance in effect right now.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor
                .withAlphaComponent(0.92).cgColor
            layer?.borderColor = NSColor.separatorColor
                .withAlphaComponent(0.7).cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Layout

    /// The time label is sized to its widest possible reading ("88:88:88"),
    /// not to the current one, so the layout never shifts as the clock ticks.
    /// The date tile is sized the same way; only turning the date on or off
    /// changes the width of the card.
    private func layoutContents() {
        let font = timeLabel.font ?? .systemFont(ofSize: 15)
        let template: String
        switch (Prefs.use24Hour, Prefs.showSeconds) {
        case (true, true):   template = "88:88:88"
        case (true, false):  template = "88:88"
        case (false, true):  template = "88:88:88 PM"
        case (false, false): template = "88:88 PM"
        }
        let timeWidth = ceil(width(of: template, font: font))
        let height = bounds.height

        var timeX = Metric.inset
        if !dateTile.isHidden {
            let tileWidth = dateTile.fittingWidth
            dateTile.frame = NSRect(x: Metric.tileInset,
                                    y: (height - DateTile.Metric.size.height).rounded() / 2,
                                    width: tileWidth,
                                    height: DateTile.Metric.size.height)
            timeX = Metric.tileInset + tileWidth + Metric.tileGap
        }

        // Everything right of the time keeps the proportions of the bare card,
        // so switching the date on only ever adds width on the left.
        let cardWidth = timeX + PetView.baseSize.width - Metric.inset
        if abs(cardWidth - bounds.width) > 0.5 {
            onSizeChange?(NSSize(width: cardWidth, height: PetView.baseSize.height))
        }

        timeLabel.frame = NSRect(x: timeX,
                                 y: (height - 18).rounded() / 2,
                                 width: timeWidth,
                                 height: 18)

        let zoneX = timeX + timeWidth + Metric.gap
        let zoneWidth = cardWidth - Metric.inset - zoneX
        zoneLabel.frame = NSRect(x: zoneX,
                                 y: (height - 14).rounded() / 2,
                                 width: max(zoneWidth, 0),
                                 height: 14)
        // In 12-hour + seconds the time alone nearly fills the card; rather
        // than show two truncated characters, drop the zone label entirely.
        zoneLabel.isHidden = zoneWidth < Metric.minZoneWidth

        gearButton.frame = NSRect(x: cardWidth - Metric.gearInset - Metric.gear,
                                  y: (height - Metric.gear) / 2,
                                  width: Metric.gear,
                                  height: Metric.gear)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContents()
    }

    private func width(of string: String, font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    // MARK: - Content

    func setTime(_ text: String) {
        timeLabel.stringValue = text
    }

    /// `nil` means the user turned the date off.
    func setDate(_ badge: DateBadge?) {
        guard let badge = badge else {
            guard !dateTile.isHidden else { return }
            dateTile.isHidden = true
            layoutContents()
            return
        }
        dateTile.set(badge)
        dateTile.isHidden = false
        layoutContents()
    }

    func setZone(label: String, tooltip: String) {
        zoneLabel.stringValue = label.uppercased()
        toolTip = tooltip
        layoutContents()
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        // .activeAlways: the pet reacts even when another app is frontmost,
        // which is the whole point of a desktop pet.
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateControls()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateControls()
    }

    /// Keeps the gear up while its menu is open, even if the pointer wanders off.
    func setMenuOpen(_ open: Bool) {
        menuOpen = open
        updateControls()
    }

    private func updateControls() {
        let show = hovering || menuOpen
        guard show != controlsShown else { return }
        controlsShown = show

        if show { gearButton.isHidden = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Metric.fade
            gearButton.animator().alphaValue = show ? 1 : 0
            zoneLabel.animator().alphaValue = show ? 0 : 1
        }, completionHandler: { [weak self] in
            guard let self = self, !self.controlsShown else { return }
            // Hide once faded out: an alpha-0 button is still clickable in AppKit.
            self.gearButton.isHidden = true
        })
    }

    @objc private func gearTapped() {
        onGear?(gearButton)
    }
}
