import Foundation
import CoreData

@objc(TowerEventEntity)
public class TowerEventEntity: NSManagedObject {
    
    // Convert to TowerEvent model
    func toTowerEvent() -> TowerEvent {
        let towerType = TowerEvent.TowerType(rawValue: self.towerType ?? "") ?? .unknown
        return TowerEvent(
            timestamp: timestamp ?? Date(),
            towerType: towerType,
            isPlayerTower: isPlayerTower,
            sessionId: session?.id ?? UUID()
        )
    }
    
    // Update from TowerEvent model
    func update(from event: TowerEvent) {
        self.timestamp = event.timestamp
        self.towerType = event.towerType.rawValue
        self.isPlayerTower = event.isPlayerTower
    }
}