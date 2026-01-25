import SwiftUI

@main
struct LisnaiApp: App {
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingManager)
                .environmentObject(locationManager)
        }
    }
}
