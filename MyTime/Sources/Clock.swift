import Foundation

/// The calendar half of what the card shows: the weekday, and the month/day,
/// both already formatted for the user's locale and the chosen zone.
struct DateBadge: Equatable {
    let weekday: String
    let monthDay: String
}

/// The ticking half of the pet. One non-repeating timer that re-aims at the
/// next real second boundary after every fire, so it cannot accumulate drift
/// the way a repeating 1.0s timer does.
final class Clock {
    private let onTime: (String) -> Void
    private let onDate: (DateBadge?) -> Void
    private var formatter = DateFormatter()
    private var weekdayFormatter = DateFormatter()
    private var monthDayFormatter = DateFormatter()
    private var timer: Timer?
    private var lastText = ""
    private var lastBadge: DateBadge?

    init(onTime: @escaping (String) -> Void, onDate: @escaping (DateBadge?) -> Void) {
        self.onTime = onTime
        self.onDate = onDate
        rebuild()
    }

    deinit { timer?.invalidate() }

    /// Rebuild the formatters after a settings change. Constructing a
    /// DateFormatter is expensive; formatting with one is not, so we keep them
    /// alive and only replace them when the zone or format actually changes.
    func rebuild() {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")   // stable, not user-locale dependent
        f.timeZone = Prefs.timeZone
        switch (Prefs.use24Hour, Prefs.showSeconds) {
        case (true, true):   f.dateFormat = "HH:mm:ss"
        case (true, false):  f.dateFormat = "HH:mm"
        case (false, true):  f.dateFormat = "h:mm:ss a"
        case (false, false): f.dateFormat = "h:mm a"
        }
        formatter = f

        // The date, unlike the time, follows the user's locale: a weekday is a
        // word, and "9/3" and "3/9" mean opposite things in different places.
        weekdayFormatter = calendarFormatter(template: "EEE")
        monthDayFormatter = calendarFormatter(template: "Md")

        lastText = ""
        // lastBadge is deliberately kept: it is what tells render() that the
        // badge just went away when the user turned the date off.
        restart()
    }

    private func calendarFormatter(template: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = .current
        f.timeZone = Prefs.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }

    func restart() {
        stop()
        render()
        schedule()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func render() {
        let now = Date()

        let text = formatter.string(from: now)
        if text != lastText {                    // no redraw when nothing changed
            lastText = text
            onTime(text)
        }

        let badge = Prefs.showDate
            ? DateBadge(weekday: weekdayFormatter.string(from: now),
                        monthDay: monthDayFormatter.string(from: now))
            : nil
        if badge != lastBadge {                  // in practice: once a day
            lastBadge = badge
            onDate(badge)
        }
    }

    private func schedule() {
        let period: TimeInterval = Prefs.showSeconds ? 1 : 60
        let now = Date().timeIntervalSince1970
        var delay = period - now.truncatingRemainder(dividingBy: period)
        if delay < 0.02 { delay += period }      // never fire twice inside one boundary

        let t = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            self?.render()
            self?.schedule()
        }
        // Lets macOS coalesce our wakeup with others it was going to make
        // anyway - meaningfully cheaper on battery than an exact-fire timer.
        t.tolerance = period * 0.05
        // .common keeps the clock ticking while the pet is being dragged or
        // while its menu is open; the default mode would freeze it.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
