import Foundation

// MARK: - Tower Event Model
struct TowerEvent: Codable, Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let towerType: TowerType
    let isPlayerTower: Bool
    let sessionId: UUID
    
    enum TowerType: String, Codable, CaseIterable {
        case king = "King Tower"
        case princess = "Princess Tower"
        case unknown = "Unknown"
        
        var displayName: String {
            switch self {
            case .king: return "King Tower"
            case .princess: return "Princess Tower"
            case .unknown: return "Tower"
            }
        }
    }
}

// MARK: - Game Session Model
struct GameSession: Codable, Identifiable {
    let id: UUID = UUID()
    let startTime: Date
    var endTime: Date?
    var playerTowersLost: Int = 0
    var enemyTowersDestroyed: Int = 0
    
    var duration: TimeInterval {
        guard let endTime = endTime else {
            return Date().timeIntervalSince(startTime)
        }
        return endTime.timeIntervalSince(startTime)
    }
    
    var isActive: Bool {
        endTime == nil
    }
}

// MARK: - Shared Constants (Legacy - Use AppConfiguration instead)
struct SharedConstants {
    static let appGroupIdentifier = "group.com.clashmonitor.shared2"
    static let broadcastStatusKey = "isBroadcasting"
    static let currentSessionKey = "currentSession"
    static let towerEventsKey = "towerEvents"
    static let notificationCooldown: TimeInterval = 5.0
}