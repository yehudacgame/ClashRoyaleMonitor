import Foundation
import SwiftUI
import CoreData

class DashboardViewModel: ObservableObject {
    @Published var currentSession: SessionEntity?
    @Published var recentEvents: [TowerEventEntity] = []
    
    private let persistenceController = PersistenceController.shared
    private let sharedDefaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
    
    init() {
        loadCurrentSession()
        loadRecentEvents()
        setupNotificationObservers()
    }
    
    func loadCurrentSession() {
        let activeSessions = persistenceController.fetchActiveSessions()
        currentSession = activeSessions.first
    }
    
    func loadRecentEvents() {
        recentEvents = persistenceController.fetchRecentTowerEvents(limit: 10)
    }
    
    func startNewSession() {
        currentSession = persistenceController.createSession()
        
        // Also store session ID in shared defaults for broadcast extension
        sharedDefaults?.set(currentSession?.id?.uuidString, forKey: "currentSessionId")
    }
    
    func stopMonitoring() {
        // Stop the broadcast extension
        sharedDefaults?.set(false, forKey: SharedConstants.broadcastStatusKey)
        
        // End current session
        if let session = currentSession {
            persistenceController.endSession(session)
        }
        
        // Clear session ID from shared defaults
        sharedDefaults?.removeObject(forKey: "currentSessionId")
        
        currentSession = nil
    }
    
    func launchCallOfDuty() {
        let codMobileURL = URL(string: "codmobile://")!
        let appStoreURL = URL(string: "https://apps.apple.com/app/call-of-duty-mobile/id1287282214")!
        
        if UIApplication.shared.canOpenURL(codMobileURL) {
            UIApplication.shared.open(codMobileURL)
        } else {
            UIApplication.shared.open(appStoreURL)
        }
    }
    
    private func setupNotificationObservers() {
        // Listen for tower events from broadcast extension
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTowerEvent),
            name: NSNotification.Name("TowerEventDetected"),
            object: nil
        )
        
        // Refresh data periodically when app is active
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.loadCurrentSession()
            self?.loadRecentEvents()
        }
    }
    
    @objc private func handleTowerEvent(_ notification: Notification) {
        loadCurrentSession()
        loadRecentEvents()
    }
}