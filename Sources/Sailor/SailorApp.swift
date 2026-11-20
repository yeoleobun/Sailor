import AppKit

@main
@MainActor
final class SailorAppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var anchorIconView: AnchorStatusIconView!
    private var menu: NSMenu!
    private var store: SailorStore!

    static func main() {
        let app = NSApplication.shared
        let delegate = SailorAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Pure menu-bar utility
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store = SailorStore()

        // Create Status Item with custom animated Anchor view
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            anchorIconView = AnchorStatusIconView(frame: button.bounds)
            anchorIconView.autoresizingMask = [.width, .height]
            button.addSubview(anchorIconView)
            button.toolTip = "Sailor"
        }

        // Native NSMenu automatically adopts macOS 26+ built-in Liquid Glass styling
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Trigger the pendulum swing animation whenever the network location switches
        store.onProfileSwitched = { [weak self] in
            self?.anchorIconView?.triggerPendulumSwing()
        }

        // Subtle welcome swing on launch
        if store.swingAnimationEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.anchorIconView?.triggerPendulumSwing()
            }
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        store.refreshAll()
        rebuildMenu(menu)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // 1. Current Recognized Wi-Fi
        menu.addItem(NSMenuItem.sectionHeader(title: "Current Network"))

        if let ssid = store.currentSSID, !ssid.isEmpty {
            let wifiItem = NSMenuItem(title: ssid, action: nil, keyEquivalent: "")
            wifiItem.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: "Wi-Fi")
            wifiItem.isEnabled = false
            menu.addItem(wifiItem)
        } else if store.needsLocationPermission {
            let permItem = NSMenuItem(
                title: "Allow Location to Read Wi-Fi…",
                action: #selector(requestLocationPermission),
                keyEquivalent: ""
            )
            permItem.target = self
            permItem.image = NSImage(systemSymbolName: "location.slash", accessibilityDescription: "Location Required")
            menu.addItem(permItem)
        } else {
            let offlineItem = NSMenuItem(title: "Not Connected to Wi-Fi", action: nil, keyEquivalent: "")
            offlineItem.image = NSImage(systemSymbolName: "wifi.slash", accessibilityDescription: "Offline")
            offlineItem.isEnabled = false
            menu.addItem(offlineItem)
        }

        menu.addItem(.separator())

        // 2. System-Configured Network Locations (picking one switches & remembers for current Wi-Fi)
        menu.addItem(NSMenuItem.sectionHeader(title: "Network Location"))

        if store.locations.isEmpty {
            let emptyItem = NSMenuItem(title: "No Locations Found", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for location in store.locations {
                let item = NSMenuItem(
                    title: location.name,
                    action: #selector(selectLocationItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = location
                item.state = location.isCurrent ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // 3. Remembered Wi-Fi -> Location mappings (submenu, no dashboard needed)
        let rememberedItem = NSMenuItem(title: "Remembered Networks", action: nil, keyEquivalent: "")
        let rememberedSubmenu = NSMenu()
        let sortedPairs = store.rememberedLocations.sorted {
            $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
        }

        if sortedPairs.isEmpty {
            let noneItem = NSMenuItem(title: "None Yet", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            rememberedSubmenu.addItem(noneItem)
        } else {
            for (ssid, locName) in sortedPairs {
                let pairItem = NSMenuItem(title: "\(ssid) → \(locName)", action: nil, keyEquivalent: "")
                let pairSubmenu = NSMenu()
                let forgetItem = NSMenuItem(
                    title: "Forget \"\(ssid)\"",
                    action: #selector(forgetSSIDItem(_:)),
                    keyEquivalent: ""
                )
                forgetItem.target = self
                forgetItem.representedObject = ssid
                pairSubmenu.addItem(forgetItem)
                pairItem.submenu = pairSubmenu
                rememberedSubmenu.addItem(pairItem)
            }
            rememberedSubmenu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear All…", action: #selector(clearAllRemembered), keyEquivalent: "")
            clearItem.target = self
            rememberedSubmenu.addItem(clearItem)
        }
        rememberedItem.submenu = rememberedSubmenu
        menu.addItem(rememberedItem)

        // 4. Toggles & System Settings Jump
        let autoSwitchItem = NSMenuItem(
            title: "Auto-Switch",
            action: #selector(toggleAutoSwitch),
            keyEquivalent: ""
        )
        autoSwitchItem.target = self
        autoSwitchItem.state = store.autoSwitchEnabled ? .on : .off
        menu.addItem(autoSwitchItem)

        let swingItem = NSMenuItem(
            title: "Swing Animation",
            action: #selector(toggleSwingAnimation),
            keyEquivalent: ""
        )
        swingItem.target = self
        swingItem.state = store.swingAnimationEnabled ? .on : .off
        menu.addItem(swingItem)

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = store.launchAtLogin ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let networkSettingsItem = NSMenuItem(
            title: "Network Settings…",
            action: #selector(openNetworkSettings),
            keyEquivalent: ""
        )
        networkSettingsItem.target = self
        menu.addItem(networkSettingsItem)

        let quitItem = NSMenuItem(
            title: "Quit Sailor",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func selectLocationItem(_ sender: NSMenuItem) {
        guard let location = sender.representedObject as? NetworkLocation else { return }
        store.selectLocation(location)
    }

    @objc private func forgetSSIDItem(_ sender: NSMenuItem) {
        guard let ssid = sender.representedObject as? String else { return }
        store.forgetSSID(ssid)
    }

    @objc private func clearAllRemembered() {
        store.clearAllRemembered()
    }

    @objc private func toggleAutoSwitch() {
        store.autoSwitchEnabled.toggle()
    }

    @objc private func toggleSwingAnimation() {
        store.swingAnimationEnabled.toggle()
        if store.swingAnimationEnabled {
            anchorIconView?.triggerPendulumSwing()
        }
    }

    @objc private func toggleLaunchAtLogin() {
        store.setLaunchAtLogin(!store.launchAtLogin)
    }

    @objc private func requestLocationPermission() {
        store.requestLocationPermission()
    }

    @objc private func openNetworkSettings() {
        store.openNetworkSettings()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
