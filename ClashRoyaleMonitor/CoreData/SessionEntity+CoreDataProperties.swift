import Foundation
import CoreData

extension SessionEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<SessionEntity> {
        return NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var startTime: Date?
    @NSManaged public var endTime: Date?
    @NSManaged public var playerTowersLost: Int16
    @NSManaged public var enemyTowersDestroyed: Int16
    @NSManaged public var towerEvents: NSSet?
    
}

// MARK: Generated accessors for towerEvents
extension SessionEntity {
    
    @objc(addTowerEventsObject:)
    @NSManaged public func addToTowerEvents(_ value: TowerEventEntity)
    
    @objc(removeTowerEventsObject:)
    @NSManaged public func removeFromTowerEvents(_ value: TowerEventEntity)
    
    @objc(addTowerEvents:)
    @NSManaged public func addToTowerEvents(_ values: NSSet)
    
    @objc(removeTowerEvents:)
    @NSManaged public func removeFromTowerEvents(_ values: NSSet)
    
}

extension SessionEntity : Identifiable {
    
}