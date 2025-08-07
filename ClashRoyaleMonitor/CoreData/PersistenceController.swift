import CoreData
import Foundation

class PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "ClashRoyaleMonitor")
        
        // Configure for app group to share data with extension
        let appGroupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier
        )
        
        if let appGroupURL = appGroupURL {
            let storeURL = appGroupURL.appendingPathComponent("ClashRoyaleMonitor.sqlite")
            let description = NSPersistentStoreDescription(url: storeURL)
            container.persistentStoreDescriptions = [description]
        }
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        container.loadPersistentStores { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }
        
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
    
    // MARK: - Preview Support
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Create sample data for previews
        for i in 0..<5 {
            let session = SessionEntity(context: viewContext)
            session.id = UUID()
            session.startTime = Date().addingTimeInterval(TimeInterval(-i * 86400))
            session.endTime = session.startTime?.addingTimeInterval(TimeInterval(1800))
            session.enemyTowersDestroyed = Int16.random(in: 0...3)
            session.playerTowersLost = Int16.random(in: 0...3)
        }
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        
        return result
    }()
    
    // MARK: - Save Context
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// MARK: - Core Data Operations
extension PersistenceController {
    
    // MARK: - Session Operations
    func createSession() -> SessionEntity {
        let context = container.viewContext
        let session = SessionEntity(context: context)
        session.id = UUID()
        session.startTime = Date()
        save()
        return session
    }
    
    func endSession(_ session: SessionEntity) {
        session.endTime = Date()
        save()
    }
    
    func fetchActiveSessions() -> [SessionEntity] {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "endTime == nil")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.startTime, ascending: false)]
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Error fetching active sessions: \(error)")
            return []
        }
    }
    
    func fetchSessions(from startDate: Date? = nil, to endDate: Date? = nil) -> [SessionEntity] {
        let request: NSFetchRequest<SessionEntity> = SessionEntity.fetchRequest()
        
        var predicates: [NSPredicate] = []
        
        if let startDate = startDate {
            predicates.append(NSPredicate(format: "startTime >= %@", startDate as NSDate))
        }
        
        if let endDate = endDate {
            predicates.append(NSPredicate(format: "startTime <= %@", endDate as NSDate))
        }
        
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        
        request.sortDescriptors = [NSSortDescriptor(keyPath: \SessionEntity.startTime, ascending: false)]
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Error fetching sessions: \(error)")
            return []
        }
    }
    
    // MARK: - Tower Event Operations
    func createTowerEvent(
        session: SessionEntity,
        towerType: TowerEvent.TowerType,
        isPlayerTower: Bool
    ) -> TowerEventEntity {
        let context = container.viewContext
        let event = TowerEventEntity(context: context)
        event.id = UUID()
        event.timestamp = Date()
        event.towerType = towerType.rawValue
        event.isPlayerTower = isPlayerTower
        event.session = session
        
        // Update session counts
        if isPlayerTower {
            session.playerTowersLost += 1
        } else {
            session.enemyTowersDestroyed += 1
        }
        
        save()
        return event
    }
    
    func fetchRecentTowerEvents(limit: Int = 10) -> [TowerEventEntity] {
        let request: NSFetchRequest<TowerEventEntity> = TowerEventEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TowerEventEntity.timestamp, ascending: false)]
        request.fetchLimit = limit
        
        do {
            return try container.viewContext.fetch(request)
        } catch {
            print("Error fetching tower events: \(error)")
            return []
        }
    }
    
    // MARK: - Statistics Operations
    func calculateStatistics(for timeRange: StatisticsView.TimeRange) -> OverallStats {
        let sessions = fetchSessionsForTimeRange(timeRange)
        
        var stats = OverallStats()
        stats.totalSessions = sessions.count
        
        for session in sessions {
            stats.enemyTowersDestroyed += Int(session.enemyTowersDestroyed)
            stats.playerTowersLost += Int(session.playerTowersLost)
            
            if let startTime = session.startTime,
               let endTime = session.endTime {
                stats.totalPlayTime += endTime.timeIntervalSince(startTime)
            }
        }
        
        return stats
    }
    
    private func fetchSessionsForTimeRange(_ timeRange: StatisticsView.TimeRange) -> [SessionEntity] {
        let calendar = Calendar.current
        let now = Date()
        let startDate: Date?
        
        switch timeRange {
        case .day:
            startDate = calendar.date(byAdding: .day, value: -1, to: now)
        case .week:
            startDate = calendar.date(byAdding: .weekOfYear, value: -1, to: now)
        case .month:
            startDate = calendar.date(byAdding: .month, value: -1, to: now)
        case .all:
            startDate = nil
        }
        
        return fetchSessions(from: startDate, to: now)
    }
    
    // MARK: - Data Management
    func deleteAllData() {
        let sessionRequest: NSFetchRequest<NSFetchRequestResult> = SessionEntity.fetchRequest()
        let deleteSessionRequest = NSBatchDeleteRequest(fetchRequest: sessionRequest)
        
        let eventRequest: NSFetchRequest<NSFetchRequestResult> = TowerEventEntity.fetchRequest()
        let deleteEventRequest = NSBatchDeleteRequest(fetchRequest: eventRequest)
        
        do {
            try container.viewContext.execute(deleteSessionRequest)
            try container.viewContext.execute(deleteEventRequest)
            save()
        } catch {
            print("Error deleting all data: \(error)")
        }
    }
}

// MARK: - Managed Object Extensions
extension SessionEntity {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        startTime = Date()
    }
}

extension TowerEventEntity {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        timestamp = Date()
    }
}