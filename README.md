# AloeNotch

> The app is branded **AloeNotch** (product name, bundle id `com.kadeslab.AloeNotch`).
> The Xcode project, scheme, source folder, and `.entitlements` are still named
> `OpenNotch` internally — that name is not user-visible, so it was left as-is to
> avoid a risky project-file rename. Build commands below use the `OpenNotch` scheme.

A small macOS menu-notch utility in the spirit of *The Boring Notch* / Alcove.
It draws a floating panel that hugs the MacBook notch, expands on hover, and
shows:

- **Now Playing from any app** — art, title/artist, play·pause·skip, and a
  draggable progress scrubber. Works with Apple Music, Spotify, and browser
  tabs (YouTube) via the vendored [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter).
- **Ambient glow** — the artwork's dominant color traces the panel's edge.
- **A drag-and-drop shelf** — stage files in the notch; they **persist across
  launches**, drag one back out, or use **Drag all** to pull them all at once.
- **Calendar & weather** — the next 24 hours of events plus local conditions.
- **A battery / charging indicator** — animated bolt + fill bar while charging.
- **A menu-bar switchboard + Settings window** — toggle each module, launch at
  login, and nudge the panel's horizontal position.

It runs as a menu-bar accessory (no Dock icon) and works on notched Macs as well
as non-notch Macs / external displays (where it renders a simulated strip).

## Requirements

- macOS 26 (Tahoe) or later — the UI is built on Liquid Glass
- Apple Silicon. 0.6.0 is the final Intel / macOS 15 release and is no longer
  maintained; it stays downloadable from [aloenotch.com](https://aloenotch.com/#download).
- Xcode 26 or later

## Build & run

1. Open `OpenNotch.xcodeproj` in Xcode.
2. Select the **OpenNotch** scheme (already shared) and a **My Mac** run destination.
3. Set a signing identity — see below.
4. Press **⌘R**. The panel appears at the top-center of your screen; hover it to
   expand. Use the menu-bar icon to reposition or quit.

## Signing

The project is set to sign with a certificate named **AloeNotch Signing**. If
you don't have it, the build fails with "No signing certificate found" — set
**Signing & Capabilities → Signing Certificate** to *Sign to Run Locally*, or
create your own certificate as below.

### Why not just sign ad-hoc?

Because ad-hoc signing makes the app's designated requirement a hash of the
binary:

```
designated => cdhash H"6f08e071…"
```

macOS privacy permissions are keyed to that requirement, so **every rebuild is
a different app** to the system — Calendar, Location and Accessibility grants
are silently discarded each time you build, and each time a user installs an
update. With a stable certificate the requirement becomes:

```
designated => identifier "com.kadeslab.AloeNotch" and certificate root = H"c90b8b3f…"
```

which is identical across builds, so permissions persist.

### Creating a signing certificate

Keychain Access → **Certificate Assistant → Create a Certificate…**, name it
`AloeNotch Signing`, Identity Type *Self Signed Root*, Certificate Type *Code
Signing*.

**Back it up.** Export it from Keychain Access (including the private key) and
store it somewhere safe. Signing a future release with a *different* identity
resets every user's permissions again, so the certificate is effectively part
of the app's identity — losing it is a one-way door.

A paid Developer ID certificate is strictly better if you have one: same
stability, plus notarization, which removes the Gatekeeper warning on first
launch. Set `SIGN_IDENTITY` when building the DMG:

```sh
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/make-dmg.sh
```

## Tests

```sh
./scripts/run-tests.sh
```

Pure logic only (panel-state precedence, version comparison), compiled directly
without an Xcode target so it runs in about a second.

## How it works

| Area | File(s) | Notes |
|------|---------|-------|
| App entry / lifecycle | `OpenNotchApp.swift`, `AppDelegate.swift` | Accessory app + `MenuBarExtra` |
| Notch geometry | `Notch/NotchGeometry.swift` | Uses `NSScreen.safeAreaInsets` + auxiliary areas |
| Floating window | `Notch/NotchPanel.swift`, `NotchWindowController.swift` | Borderless non-activating `NSPanel` above the menu bar |
| Click-through | `Notch/PassthroughHostingView.swift` | Only the active notch rect receives mouse events |
| Shared state | `Notch/NotchViewModel.swift` | Owns the feature managers + expand state |
| UI | `Views/*` | SwiftUI collapsed/expanded content |
| Media | `Media/*` | mediaremote-adapter engine + legacy bridge + now-playing manager |
| Shelf | `Tray/TrayModel.swift`, `Views/TrayView.swift` | File staging, persisted via bookmarks |
| Settings | `Settings/AppSettings.swift`, `Views/SettingsView.swift`, `Views/SettingsMenuView.swift` | Preferences window + menu-bar switchboard |
| Battery | `Battery/BatteryMonitor.swift`, `Views/BatteryView.swift` | IOKit power sources |

## Important caveats

- **Now Playing uses a private framework.** `MediaRemote` is undocumented, and on
  **macOS 15.4+ Apple restricted its now-playing read APIs for third-party apps.**
  The code loads it dynamically and degrades gracefully: if it's unavailable the
  media panel shows "Now Playing unavailable" instead of crashing. Because it's
  private API, an app using it **cannot ship on the Mac App Store** and could
  break on any macOS update. For a distributable version you'd want a supported
  alternative (e.g. per-app scripting bridges, or Apple's public frameworks where
  they cover your need).

## Done since the initial scaffold

- Shelf persistence across launches (file bookmarks) + **Drag all** multi-file drag-out.
- A proper Settings window (module toggles, position offset) plus a menu-bar switchboard.
- Launch-at-login via `SMAppService`.
- A real app icon (generated by `scripts/generate-icon.swift`).
- Song scrubber with live-interpolated elapsed time and drag-to-seek.

## Suggested next steps

- Per-app now-playing source picker when multiple apps are playing.
- Optional lyrics / larger media view; keyboard shortcut to toggle the panel.
- A signed + notarized build so first-launch skips the Gatekeeper prompt.
