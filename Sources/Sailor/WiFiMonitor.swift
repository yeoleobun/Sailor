import CoreLocation
import CoreWLAN
import Foundation
import Network

/// Monitors Wi-Fi SSID changes reactively using CoreWLAN + NWPathMonitor,
/// and handles macOS 14+ Location Services authorization required to read SSIDs.
final class WiFiMonitor: NSObject, @unchecked Sendable {
    var onSSIDChange: (@Sendable (String?) -> Void)?
    var onAuthorizationChange: (@Sendable (CLAuthorizationStatus) -> Void)?

    private let wifiClient = CWWiFiClient.shared()
    private let locationManager = CLLocationManager()
    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.sailor.wifimonitor", qos: .utility)

    private var lastReportedSSID: String?
    private var hasReportedInitial = false

    override init() {
        super.init()
        locationManager.delegate = self
        wifiClient.delegate = self
    }

    var authorizationStatus: CLAuthorizationStatus {
        locationManager.authorizationStatus
    }

    func start() {
        requestLocationPermissionIfNeeded()

        do {
            try wifiClient.startMonitoringEvent(with: .ssidDidChange)
            try wifiClient.startMonitoringEvent(with: .powerDidChange)
            try wifiClient.startMonitoringEvent(with: .linkDidChange)
        } catch {
            // NWPathMonitor still serves as a reliable fallback
        }

        pathMonitor.pathUpdateHandler = { [weak self] _ in
            self?.refreshSSID(forceNotify: false)
        }
        pathMonitor.start(queue: monitorQueue)

        // Emit initial state
        refreshSSID(forceNotify: true)
    }

    func stop() {
        try? wifiClient.stopMonitoringAllEvents()
        pathMonitor.cancel()
    }

    func requestLocationPermissionIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            DispatchQueue.main.async { [weak self] in
                self?.locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    func currentSSID() -> String? {
        if let ssid = wifiClient.interface()?.ssid(), !ssid.isEmpty {
            return ssid
        }
        return nil
    }

    func refreshSSID(forceNotify: Bool = false) {
        monitorQueue.async { [weak self] in
            guard let self else { return }
            let ssid = self.currentSSID()
            if forceNotify || !self.hasReportedInitial || ssid != self.lastReportedSSID {
                self.hasReportedInitial = true
                self.lastReportedSSID = ssid
                self.onSSIDChange?(ssid)
            }
        }
    }
}

extension WiFiMonitor: CWEventDelegate {
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        refreshSSID(forceNotify: false)
    }

    func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        refreshSSID(forceNotify: false)
    }

    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        refreshSSID(forceNotify: false)
    }
}

extension WiFiMonitor: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        onAuthorizationChange?(status)
        refreshSSID(forceNotify: true)
    }
}
