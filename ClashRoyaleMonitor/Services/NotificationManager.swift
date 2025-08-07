import UserNotifications
import SwiftUI

class NotificationManager: NSObject, ObservableObject {
    @Published var isAuthorized = false
    private let notificationCenter = UNUserNotificationCenter.current()
    
    override init() {
        super.init()
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }
    
    func requestAuthorization() {
        notificationCenter.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.isAuthorized = granted
                if granted {
                    self?.setupNotificationCategories()
                }
            }
        }
    }
    
    private func checkAuthorizationStatus() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func setupNotificationCategories() {
        let playerTowerCategory = UNNotificationCategory(
            identifier: "PLAYER_TOWER_DESTROYED",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        let enemyTowerCategory = UNNotificationCategory(
            identifier: "ENEMY_TOWER_DESTROYED",
            actions: [],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        notificationCenter.setNotificationCategories([playerTowerCategory, enemyTowerCategory])
    }
    
    func sendTowerNotification(event: TowerEvent) {
        let content = UNMutableNotificationContent()
        
        if event.isPlayerTower {
            content.title = "Tower Lost!"
            content.body = "Your \(event.towerType.displayName) has been destroyed"
            content.categoryIdentifier = "PLAYER_TOWER_DESTROYED"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("tower_lost.caf"))
        } else {
            content.title = "Tower Destroyed!"
            content.body = "Enemy \(event.towerType.displayName) has been destroyed"
            content.categoryIdentifier = "ENEMY_TOWER_DESTROYED"
            content.sound = UNNotificationSound(named: UNNotificationSoundName("tower_destroyed.caf"))
        }
        
        content.badge = NSNumber(value: 1)
        content.userInfo = [
            "eventId": event.id.uuidString,
            "timestamp": event.timestamp.timeIntervalSince1970
        ]
        
        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil
        )
        
        notificationCenter.add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification tap
        completionHandler()
    }
}