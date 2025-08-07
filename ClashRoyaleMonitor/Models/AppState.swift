import SwiftUI
import Foundation

// MARK: - App State
class AppState: ObservableObject {
    @Published var showOnboarding = false
    @Published var isMonitoring = false
    @Published var currentTab = 0
    
    func checkBroadcastStatus() {
        // Check if broadcast extension is active
        let sharedDefaults = UserDefaults(suiteName: "group.com.clashmonitor.shared2")
        isMonitoring = sharedDefaults?.bool(forKey: "isBroadcasting") ?? false
    }
}