import AppKit

/// The floating window the pet lives in: borderless, transparent, always on
/// top, and draggable from anywhere on its background.
final class PetPanel: NSPanel {

    init(content: NSView) {
        super.init(contentRect: NSRect(origin: .zero, size: content.frame.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        contentView = content

        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear          // the rounded card is drawn by PetView
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true // dragging, for free, from AppKit
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none

        // Follow the user across Spaces and sit above full-screen apps, like a
        // pet should - but never steal a slot in Cmd-Tab or the window cycle.
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
    }

    // A borderless panel refuses key status unless we say otherwise.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
