import SwiftUI

@main
struct AloeNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The visible UI lives in a floating NSPanel managed by AppDelegate.
        // This MenuBarExtra hosts the settings panel, since the app runs as an
        // accessory (LSUIElement) with no Dock icon.
        MenuBarExtra("AloeNotch", systemImage: "rectangle.topthird.inset.filled") {
            SettingsMenuView(
                onReposition: { appDelegate.notchController?.repositionOnActiveScreen() }
            )
        }
        .menuBarExtraStyle(.window)
    }
}
