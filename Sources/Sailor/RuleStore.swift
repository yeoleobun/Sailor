import AppKit
import CoreLocation
import Foundation
import ServiceManagement

struct SailorConfig: Codable {
    var autoSwitchEnabled: Bool = true
    var swingAnimationEnabled: Bool = true
    /// Maps recognized Wi-Fi SSID -> last chosen macOS Network Location name.
    var rememberedLocations: [String: String] = [:]
}

@MainActor
final class SailorStore {
    var autoSwitchEnabled: Bool = true {
        didSet {
            saveConfig()
            if autoSwitchEnabled { evaluateAutoSwitch() }
        }
    }

    var swingAnimationEnabled: Bool = true {
        didSet { saveConfig() }
    }

    /// Remembered mapping of Wi-Fi SSID -> macOS Network Location name.
    private(set) var rememberedLocations: [String: String] = [:]

    private(set) var currentSSID: String? = nil
    private(set) var locations: [NetworkLocation] = []
    private(set) var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    private(set) var launchAtLogin: Bool = false

    /// Called whenever a network location switch succeeds (triggers the menu bar pendulum swing).
    var onProfileSwitched: (() -> Void)?

    private let locationManager = NetworkLocationManager()
    private let wifiMonitor = WiFiMonitor()
    private let configURL: URL

    var activeLocation: NetworkLocation? {
        locations.first(where: { $0.isCurrent })
    }

    var needsLocationPermission: Bool {
        locationAuthStatus != .authorized && locationAuthStatus != .authorizedAlways
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sailor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.configURL = dir.appendingPathComponent("config.json")

        loadConfig()
        refreshLaunchAtLoginState()
        refreshLocations()

        locationAuthStatus = wifiMonitor.authorizationStatus
        wifiMonitor.onSSIDChange = { [weak self] ssid in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let changed = self.currentSSID != ssid
                self.currentSSID = ssid
                self.refreshLocations()
                if changed || ssid != nil {
                    self.evaluateAutoSwitch()
                }
            }
        }
        wifiMonitor.onAuthorizationChange = { [weak self] status in
            Task { @MainActor [weak self] in
                self?.locationAuthStatus = status
            }
        }
        wifiMonitor.start()
    }

    func refreshAll() {
        refreshLocations()
        currentSSID = wifiMonitor.currentSSID()
        locationAuthStatus = wifiMonitor.authorizationStatus
    }

    func refreshLocations() {
        locations = locationManager.fetchLocations()
    }

    func requestLocationPermission() {
        wifiMonitor.requestLocationPermissionIfNeeded()
        if locationAuthStatus == .denied || locationAuthStatus == .restricted {
            openLocationSettings()
        }
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func openNetworkSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Network-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// User picked a Network Location from the menu:
    /// switches immediately AND remembers this choice for the currently recognized Wi-Fi SSID.
    func selectLocation(_ location: NetworkLocation) {
        if let ssid = currentSSID, !ssid.isEmpty {
            rememberedLocations[ssid] = location.name
            saveConfig()
        }

        do {
            try locationManager.switchLocation(to: location)
            refreshLocations()
            if swingAnimationEnabled {
                onProfileSwitched?()
            }
        } catch {
            NSSound.beep()
        }
    }

    func forgetSSID(_ ssid: String) {
        rememberedLocations.removeValue(forKey: ssid)
        saveConfig()
    }

    func clearAllRemembered() {
        rememberedLocations.removeAll()
        saveConfig()
    }

    /// Looks up the remembered location for the current Wi-Fi SSID and switches back automatically.
    func evaluateAutoSwitch() {
        guard autoSwitchEnabled else { return }
        guard let ssid = currentSSID, !ssid.isEmpty else { return }
        guard let targetName = rememberedLocations[ssid], !targetName.isEmpty else { return }

        // Already active — nothing to do
        if activeLocation?.name == targetName { return }

        do {
            try locationManager.switchLocation(named: targetName)
            refreshLocations()
            if swingAnimationEnabled {
                onProfileSwitched?()
            }
        } catch {
            // Silently ignore if the remembered location was removed in System Settings
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Requires running from signed .app bundle
        }
        refreshLaunchAtLoginState()
    }

    private func refreshLaunchAtLoginState() {
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(SailorConfig.self, from: data)
        else { return }

        self.autoSwitchEnabled = config.autoSwitchEnabled
        self.swingAnimationEnabled = config.swingAnimationEnabled
        self.rememberedLocations = config.rememberedLocations
    }

    private func saveConfig() {
        let config = SailorConfig(
            autoSwitchEnabled: autoSwitchEnabled,
            swingAnimationEnabled: swingAnimationEnabled,
            rememberedLocations: rememberedLocations
        )
        if let data = try? JSONEncoder().encode(config) {
            try? data.write(to: configURL, options: .atomic)
        }
    }
}
