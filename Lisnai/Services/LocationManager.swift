import Foundation
import CoreLocation
import UserNotifications

@MainActor
class LocationManager: NSObject, ObservableObject {
    @Published var homeLocation: CLLocation?
    @Published var isInHomeZone = true

    private let locationManager = CLLocationManager()
    private let homeZoneRadius: CLLocationDistance = 100.0 // 100 meters
    private var isSetup = false

    override init() {
        super.init()
        locationManager.delegate = self
        // Permission requests moved to lazy initialization
    }

    func requestPermissions() {
        guard !isSetup else { return }
        locationManager.requestAlwaysAuthorization()
        setupNotifications()
        isSetup = true
    }

    func setHomeLocation(_ location: CLLocation) {
        homeLocation = location

        // Create geofence region
        let region = CLCircularRegion(
            center: location.coordinate,
            radius: homeZoneRadius,
            identifier: "home-zone"
        )
        region.notifyOnEntry = true
        region.notifyOnExit = true

        // Start monitoring
        locationManager.startMonitoring(for: region)

        print("Home zone set at: \(location.coordinate.latitude), \(location.coordinate.longitude)")
    }

    func setCurrentLocationAsHome() {
        locationManager.requestLocation()
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    func sendRecordingReminder(leftHome: Bool) {
        let content = UNMutableNotificationContent()
        content.title = leftHome ? "You left home" : "You're back home"
        content.body = leftHome ? "Start recording your day?" : "Stop recording?"
        content.sound = .default
        content.categoryIdentifier = "recording-reminder"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        Task { @MainActor in
            isInHomeZone = true
            sendRecordingReminder(leftHome: false)
            print("Entered home zone")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        Task { @MainActor in
            isInHomeZone = false
            sendRecordingReminder(leftHome: true)
            print("Exited home zone")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let location = locations.first {
                setHomeLocation(location)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
