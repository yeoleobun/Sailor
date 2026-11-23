import AppKit
import CoreLocation
import Foundation
import ServiceManagement

/// User data persisted in ~/Library/Application Support/Sailor/rules.json.
struct SailorRulesData: Codable {
    /// Maps recognized Wi-Fi SSID -> last chosen macOS Network Location name.
    var rememberedLocations: [String: String] = [:]
}

/// Legacy combined config file format (~/Library/Application Support/Sailor/config.json),
/// kept solely for one-time automatic migration.
private struct LegacySailorConfig: Decodable {
    var autoSwitchEnabled: Bool = true
    var swingAnimationEnabled: Bool = true
    var fallbackLocationName: String? = "Automatic"
    var rememberedLocations: [String: String] = [:]

    enum CodingKeys: String, CodingKey {
        case autoSwitchEnabled
        case swingAnimationEnabled
        case fallbackLocationName
        case rememberedLocations
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoSwitchEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSwitchEnabled) ?? true
        swingAnimationEnabled = try c.decodeIfPresent(Bool.self, forKey: .swingAnimationEnabled) ?? true
        if c.contains(.fallbackLocationName) {
            fallbackLocationName = try c.decodeIfPresent(String.self, forKey: .fallbackLocationName)
        } else {
            fallbackLocationName = "Automatic"
        }
        rememberedLocations = try c.decodeIfPresent([String: String].self, forKey: .rememberedLocations) ?? [:]
    }
}

@MainActor
final class SailorStore {
    private enum PreferenceKey {
        static let autoSwitchEnabled = "autoSwitchEnabled"
        static let swingAnimationEnabled = "swingAnimationEnabled"
        static let fallbackLocationName = "fallbackLocationName"
    }

    var autoSwitchEnabled: Bool = true {
        didSet {
            guard !isLoading else { return }
            savePreferences()
            if autoSwitchEnabled { evaluateAutoSwitch() }
        }
    }

    var swingAnimationEnabled: Bool = true {
        didSet {
            guard !isLoading else { return }
            savePreferences()
        }
    }

    /// Location to auto-switch to for new/unrecognized Wi-Fi networks (defaults to "Automatic", nil = Do Nothing).
    var fallbackLocationName: String? = "Automatic" {
        didSet {
            guard !isLoading else { return }
            savePreferences()
            if autoSwitchEnabled { evaluateAutoSwitch() }
        }
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
    private let defaults: UserDefaults
    private let rulesURL: URL
    private let legacyConfigURL: URL
    private var isLoading = false

    var activeLocation: NetworkLocation? {
        locations.first(where: { $0.isCurrent })
    }

    var needsLocationPermission: Bool {
        locationAuthStatus != .authorized && locationAuthStatus != .authorizedAlways
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Sailor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.rulesURL = dir.appendingPathComponent("rules.json")
        self.legacyConfigURL = dir.appendingPathComponent("config.json")

        loadState()
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
            saveRules()
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
        saveRules()
    }

    func clearAllRemembered() {
        rememberedLocations.removeAll()
        saveRules()
    }

    /// Looks up the remembered location for the current Wi-Fi SSID and switches back automatically.
    /// For new/unrecognized Wi-Fi networks, switches to `fallbackLocationName` (defaults to "Automatic").
    func evaluateAutoSwitch() {
        guard autoSwitchEnabled else { return }
        guard let ssid = currentSSID, !ssid.isEmpty else { return }

        let targetName: String?
        if let remembered = rememberedLocations[ssid], !remembered.isEmpty {
            targetName = remembered
        } else if let fallback = fallbackLocationName, !fallback.isEmpty,
                  locations.contains(where: { $0.name == fallback }) {
            targetName = fallback
        } else {
            targetName = nil
        }

        guard let resolvedTarget = targetName else { return }

        // Already active — nothing to do
        if activeLocation?.name == resolvedTarget { return }

        do {
            try locationManager.switchLocation(named: resolvedTarget)
            refreshLocations()
            if swingAnimationEnabled {
                onProfileSwitched?()
            }
        } catch {
            // Silently ignore if the target location was removed in System Settings
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

    private func loadState() {
        isLoading = true
        defer { isLoading = false }

        migrateLegacyConfigIfNeeded()
        loadPreferences()
        loadRules()
    }

    private func migrateLegacyConfigIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: rulesURL.path),
              fm.fileExists(atPath: legacyConfigURL.path),
              let data = try? Data(contentsOf: legacyConfigURL),
              let legacy = try? JSONDecoder().decode(LegacySailorConfig.self, from: data)
        else { return }

        if defaults.object(forKey: PreferenceKey.autoSwitchEnabled) == nil {
            defaults.set(legacy.autoSwitchEnabled, forKey: PreferenceKey.autoSwitchEnabled)
        }
        if defaults.object(forKey: PreferenceKey.swingAnimationEnabled) == nil {
            defaults.set(legacy.swingAnimationEnabled, forKey: PreferenceKey.swingAnimationEnabled)
        }
        if defaults.object(forKey: PreferenceKey.fallbackLocationName) == nil {
            defaults.set(legacy.fallbackLocationName ?? "", forKey: PreferenceKey.fallbackLocationName)
        }

        rememberedLocations = legacy.rememberedLocations
        if saveRules() {
            try? fm.removeItem(at: legacyConfigURL)
        }
    }

    private func loadPreferences() {
        if let savedAutoSwitch = defaults.object(forKey: PreferenceKey.autoSwitchEnabled) as? Bool {
            autoSwitchEnabled = savedAutoSwitch
        }
        if let savedSwing = defaults.object(forKey: PreferenceKey.swingAnimationEnabled) as? Bool {
            swingAnimationEnabled = savedSwing
        }
        if let savedFallback = defaults.string(forKey: PreferenceKey.fallbackLocationName) {
            fallbackLocationName = savedFallback.isEmpty ? nil : savedFallback
        }
    }

    private func savePreferences() {
        defaults.set(autoSwitchEnabled, forKey: PreferenceKey.autoSwitchEnabled)
        defaults.set(swingAnimationEnabled, forKey: PreferenceKey.swingAnimationEnabled)
        defaults.set(fallbackLocationName ?? "", forKey: PreferenceKey.fallbackLocationName)
    }

    private func loadRules() {
        guard let data = try? Data(contentsOf: rulesURL),
              let rules = try? JSONDecoder().decode(SailorRulesData.self, from: data)
        else { return }

        rememberedLocations = rules.rememberedLocations
    }

    @discardableResult
    private func saveRules() -> Bool {
        let rules = SailorRulesData(rememberedLocations: rememberedLocations)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(rules) else { return false }
        do {
            try data.write(to: rulesURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
