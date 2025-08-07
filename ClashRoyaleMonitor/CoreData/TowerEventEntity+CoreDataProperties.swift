import Foundation
import CoreData

extension TowerEventEntity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<TowerEventEntity> {
        return NSFetchRequest<TowerEventEntity>(entityName: "TowerEventEntity")
    }
    
    @NSManaged public var id: UUID?
    @NSManaged public var timestamp: Date?
    @NSManaged public var towerType: String?
    @NSManaged public var isPlayerTower: Bool
    @NSManaged public var session: SessionEntity?
    
}

extension TowerEventEntity : Identifiable {
    
}