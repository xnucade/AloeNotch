# AloeNotch

> The app is branded **AloeNotch** (product name, bundle id `com.kadeslab.AloeNotch`).
> The Xcode project, scheme, source folder, and `.entitlements` are still named
> `OpenNotch` internally — that name is not user-visible, so it was left as-is to
> avoid a risky project-file rename. Build commands below use the `OpenNotch` scheme.

A small macOS menu-notch utility in the spirit of *The Boring Notch*. It draws a
floating panel that hugs the MacBook notch, expands on hover, and shows:

- **Now-playing media controls** — art, title/artist, play·pause·skip
- **A drag-and-drop shelf** — stage files in the notch, drag them back out
- **A battery / charging indicator** — animated bolt + fill bar while charging

It runs as a menu-bar accessory (no Dock icon) and works on notched Macs as well
as non-notch Macs / external displays (where it renders a simulated strip).

> Status: this is a working **MVP scaffold**. It compiles into a runnable app,
> but it hasn't been run on-device by the author — expect to tweak spacing and
> a few edge cases once you see it live.

## Requirements

- macOS 15 (Sequoia) or later
- Xcode 16 or later

## Build & run

1. Open `OpenNotch.xcodeproj` in Xcode.
2. Select the **OpenNotch** scheme (already shared) and a **My Mac** run destination.
3. In **Signing & Capabilities**, pick your Team (a free personal Apple ID is
   fine for running locally — no paid Developer account needed).
4. Press **⌘R**. The panel appears at the top-center of your screen; hover it to
   expand. Use the menu-bar icon to reposition or quit.

## How it works

| Area | File(s) | Notes |
|------|---------|-------|
| App entry / lifecycle | `OpenNotchApp.swift`, `AppDelegate.swift` | Accessory app + `MenuBarExtra` |
| Notch geometry | `Notch/NotchGeometry.swift` | Uses `NSScreen.safeAreaInsets` + auxiliary areas |
| Floating window | `Notch/NotchPanel.swift`, `NotchWindowController.swift` | Borderless non-activating `NSPanel` above the menu bar |
| Click-through | `Notch/PassthroughHostingView.swift` | Only the active notch rect receives mouse events |
| Shared state | `Notch/NotchViewModel.swift` | Owns the feature managers + expand state |
| UI | `Views/*` | SwiftUI collapsed/expanded content |
| Media | `Media/*` | MediaRemote bridge + now-playing manager |
| Tray | `Tray/TrayModel.swift`, `Views/TrayView.swift` | Session-only file staging |
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
- **No app sandbox.** Disabled on purpose so IOKit battery reads and the media
  bridge work. This is fine for a personal/local tool; revisit before distributing.
- **First launch permissions.** Nothing beyond signing is required for the current
  features, but dragging files relies on standard drag-and-drop (no Full Disk
  Access needed).

## Suggested next steps

- Persist the shelf across launches; add multi-file drag-out as a group.
- Add a proper Settings window (position offset, which modules are enabled).
- Launch-at-login via `SMAppService`.
- A real app icon (the `AppIcon` set is currently empty).
- Song scrubber / progress ring using the elapsed-time keys from MediaRemote.
