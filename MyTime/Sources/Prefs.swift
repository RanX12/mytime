import AppKit

/// Everything the pet remembers between launches.
enum Prefs {
    private static let store = UserDefaults.standard

    private static let kZone = "zone"
    private static let kH24 = "use24Hour"
    private static let kSeconds = "showSeconds"
    private static let kDate = "showDate"
    private static let kOriginX = "originX"
    private static let kOriginY = "originY"

    static func registerDefaults() {
        store.register(defaults: [kH24: true, kSeconds: true, kDate: true])
    }

    /// No stored zone means "follow the Mac", which keeps working when the
    /// user travels or the system zone changes underneath us.
    static var followsSystemZone: Bool {
        store.string(forKey: kZone) == nil
    }

    static var zoneID: String {
        get { store.string(forKey: kZone) ?? TimeZone.current.identifier }
        set { store.set(newValue, forKey: kZone) }
    }

    static var timeZone: TimeZone {
        TimeZone(identifier: zoneID) ?? .current
    }

    static func followSystemZone() {
        store.removeObject(forKey: kZone)
    }

    static var use24Hour: Bool {
        get { store.bool(forKey: kH24) }
        set { store.set(newValue, forKey: kH24) }
    }

    static var showSeconds: Bool {
        get { store.bool(forKey: kSeconds) }
        set { store.set(newValue, forKey: kSeconds) }
    }

    static var showDate: Bool {
        get { store.bool(forKey: kDate) }
        set { store.set(newValue, forKey: kDate) }
    }

    static var origin: CGPoint? {
        get {
            guard store.object(forKey: kOriginX) != nil else { return nil }
            return CGPoint(x: store.double(forKey: kOriginX),
                           y: store.double(forKey: kOriginY))
        }
        set {
            guard let point = newValue else { return }
            store.set(point.x, forKey: kOriginX)
            store.set(point.y, forKey: kOriginY)
        }
    }
}
