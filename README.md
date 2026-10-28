# MyTime

A desktop-pet clock for macOS. A 35 pt-tall card that floats above your
windows showing the date and the time; the controls appear only when the mouse
is over it.

```sh
./MyTime/build.sh
open MyTime/build/MyTime.app
```

No Xcode project, no package manager, no dependencies — `build.sh` is a single
`swiftc` invocation that assembles the `.app` bundle.

## Running with pm2

`ecosystem.config.js` runs the built binary under [pm2](https://pm2.keymetrics.io/)
as the process `mytime`. It is restarted if it crashes, but **Quit** from the
gear menu exits with code 0 and pm2 leaves it stopped (`stop_exit_codes: [0]`).

**Start**

```sh
./MyTime/build.sh                 # build first; pm2 runs MyTime/build/MyTime.app
pm2 start ecosystem.config.js
pm2 status                        # confirm `mytime` is online
```

**Save** — record the current process list so it can be restored later:

```sh
pm2 save                          # writes ~/.pm2/dump.pm2
```

Run `pm2 save` again whenever you add or remove processes; restore uses the
last saved list.

**Restore**

```sh
pm2 resurrect                     # restart everything from the last `pm2 save`
```

To restore automatically after a reboot, register pm2 with launchd once:

```sh
pm2 startup                       # prints a `sudo env PATH=... pm2 startup launchd ...` command
# copy and run the printed command, then:
pm2 save
```

Use either this or the Login Items approach below, not both, or two pets will
start.

**Day-to-day**

```sh
pm2 restart mytime                # after rebuilding with ./MyTime/build.sh
pm2 stop mytime                   # stop without removing it from pm2
pm2 logs mytime                   # stdout/stderr
pm2 delete mytime && pm2 save     # remove it and forget it on the next restore
pm2 unstartup launchd             # stop pm2 launching at login
```

## Behaviour

- **Idle:** a calendar tile — weekday over month/day — then the time, plus a
  short zone label (`PDT`, `GMT+9`).
- **Hover:** the zone label fades out and a gear fades in, inside the same
  card. Hovering never changes the card's size.
- **Gear (or right-click):** time zone, 24-hour, seconds, date, quit. The zone
  list is the full IANA database grouped by region.
- **Drag:** grab it anywhere except the gear.
- **Position is remembered** across launches, and re-clamped onto a screen that
  still exists — so a pet parked on a display you later unplug isn't lost.
- **No Dock icon, no Cmd-Tab entry** (`LSUIElement`). It joins every Space and
  floats over full-screen apps. Quit from the gear menu.

On first launch it appears at the bottom-right of the display holding the
pointer — not `NSScreen.main`, which means "screen with the key window" and on a
multi-display Mac can drop the pet on a screen you aren't looking at.

## Why Swift + AppKit

The requirement was the language that costs the least CPU and memory, and for a
native app that rules out the web stack this started as:

| | Swift + AppKit | Electron | Tauri |
|---|---|---|---|
| Idle RAM | ~15–25 MB | ~150–250 MB | ~60–90 MB |
| Ships | nothing | a whole Chromium | a WebView |
| Processes | 1 | 3+ | 2 |

An Electron build would spend roughly ten times the memory of the thing it
displays. Swift compiles to a native binary with no runtime to ship, and AppKit
gives the pet behaviours — floating panel level, drag-by-background, Spaces
membership, hover tracking — as window flags rather than as code.

## How the cost is kept near zero

- **One non-repeating timer that re-aims at the next real second boundary**
  after each fire (`period - now.truncatingRemainder(dividingBy: period)`).
  A repeating 1.0 s timer accumulates lateness and eventually skips a second.
- **`tolerance` is 5% of the period,** letting macOS coalesce the wakeup with
  ones it was already making. Meaningfully cheaper on battery than exact firing.
- **Turning seconds off drops the timer to once a minute** — 60× fewer wakeups.
- **The timer runs in `.common` run-loop mode,** so the clock keeps ticking
  while the pet is dragged or its menu is open instead of freezing.
- **No redraw unless the string changed** — the formatted value is compared
  before it is assigned.
- **Nothing ticks while the screens are asleep** (`screensDidSleep`), and the
  clock restarts on wake so it is never stale.
- **One cached `DateFormatter`,** rebuilt only on a settings change.
- **Timezone menus are built on demand:** the ~400 IANA identifiers become
  region headings up front, and a region's cities are only created the first
  time that submenu opens. Never open "Antarctica" and you never pay for it.
- **Frame-based layout, no Auto Layout** — the card's contents are four fixed
  rectangles; a constraint solver would be overkill.
- **The time label is sized to its widest possible reading** (`88:88:88`), so
  ticking never triggers a re-layout. The date tile is measured the same way —
  every digit run as `88` — so 9/3 and 12/25 occupy the same tile and midnight
  does not resize the card. Only toggling the date on or off changes its width,
  and the card then grows leftwards so the time stays where it was.
- **The date is only re-formatted into the card when it actually changes,**
  which is once a day.

## Accuracy

The time comes from the system clock, mapped into the chosen zone by Foundation
against the IANA database, so DST is the platform's problem rather than
hand-rolled offsets — and the date is the date *in that zone*, so a pet set to
Tokyo can legitimately show tomorrow. The weekday and the month/day order
follow the Mac's locale (`9/3` vs `3/9` mean opposite things in different
places); only the clock face is locale-independent. The app also listens for `NSSystemClockDidChange` and
`NSSystemTimeZoneDidChange`, so a clock correction or a zone change while
travelling is picked up immediately. If the *Mac's* clock is wrong the display
inherits that error; correcting for that needs a network time source, which this
app deliberately does not contact.

## Source

| File | Role |
|---|---|
| `Sources/main.swift` | app delegate, placement, persistence, system notifications |
| `Sources/PetPanel.swift` | the floating borderless window |
| `Sources/PetView.swift` | the card: labels, gear, hover |
| `Sources/Clock.swift` | the drift-corrected timer and formatting |
| `Sources/SettingsMenu.swift` | gear/right-click menu, lazy zone lists |
| `Sources/Prefs.swift` | what survives a relaunch |

## Notes

- The build is ad-hoc signed, which is enough for a locally built app. It is not
  notarized, so copying it to another Mac would trip Gatekeeper.
- To start it at login: System Settings → General → Login Items → add
  `MyTime.app`.
- `prototype-web/` is the earlier browser version of this widget, kept for
  reference. It is not part of the Mac app.
