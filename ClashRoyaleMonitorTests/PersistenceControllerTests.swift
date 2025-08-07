import XCTest
import CoreData
@testable import ClashRoyaleMonitor

class PersistenceControllerTests: XCTestCase {
    var persistenceController: PersistenceController!
    
    override func setUp() {
        super.setUp()
        // Use in-memory store for testing
        persistenceController = PersistenceController(inMemory: true)
    }
    
    override func tearDown() {
        persistenceController = nil
        super.tearDown()
    }
    
    // MARK: - Session Tests
    
    func testCreateSession() {
        let session = persistenceController.createSession()
        
        XCTAssertNotNil(session.id)
        XCTAssertNotNil(session.startTime)
        XCTAssertNil(session.endTime)
        XCTAssertEqual(session.playerTowersLost, 0)
        XCTAssertEqual(session.enemyTowersDestroyed, 0)
    }
    
    func testEndSession() {
        let session = persistenceController.createSession()
        let startTime = session.startTime!
        
        persistenceController.endSession(session)
        
        XCTAssertNotNil(session.endTime)
        XCTAssertTrue(session.endTime! > startTime)
    }
    
    func testFetchActiveSessions() {
        // Create active session
        let activeSession = persistenceController.createSession()
        
        // Create ended session
        let endedSession = persistenceController.createSession()
        persistenceController.endSession(endedSession)
        
        let activeSessions = persistenceController.fetchActiveSessions()
        
        XCTAssertEqual(activeSessions.count, 1)
        XCTAssertEqual(activeSessions.first?.id, activeSession.id)
    }
    
    func testFetchSessionsWithDateRange() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now)!
        
        // Create sessions with different dates
        let session1 = persistenceController.createSession()
        session1.startTime = twoDaysAgo
        
        let session2 = persistenceController.createSession()
        session2.startTime = yesterday
        
        persistenceController.save()
        
        // Fetch sessions from yesterday onwards
        let recentSessions = persistenceController.fetchSessions(from: yesterday, to: now)
        
        XCTAssertEqual(recentSessions.count, 1)
        XCTAssertEqual(recentSessions.first?.id, session2.id)
    }
    
    // MARK: - Tower Event Tests
    
    func testCreateTowerEvent() {
        let session = persistenceController.createSession()
        
        let event = persistenceController.createTowerEvent(
            session: session,
            towerType: .princess,
            isPlayerTower: false
        )
        
        XCTAssertNotNil(event.id)
        XCTAssertNotNil(event.timestamp)
        XCTAssertEqual(event.towerType, TowerEvent.TowerType.princess.rawValue)
        XCTAssertFalse(event.isPlayerTower)
        XCTAssertEqual(event.session?.id, session.id)
        
        // Check session was updated
        XCTAssertEqual(session.enemyTowersDestroyed, 1)
        XCTAssertEqual(session.playerTowersLost, 0)
    }
    
    func testCreatePlayerTowerEvent() {
        let session = persistenceController.createSession()
        
        let event = persistenceController.createTowerEvent(
            session: session,
            towerType: .king,
            isPlayerTower: true
        )
        
        XCTAssertTrue(event.isPlayerTower)
        
        // Check session was updated
        XCTAssertEqual(session.playerTowersLost, 1)
        XCTAssertEqual(session.enemyTowersDestroyed, 0)
    }
    
    func testFetchRecentTowerEvents() {
        let session = persistenceController.createSession()
        
        // Create multiple events
        for i in 0..<5 {
            let event = persistenceController.createTowerEvent(
                session: session,
                towerType: .princess,
                isPlayerTower: i % 2 == 0
            )
            // Slightly offset timestamps for ordering
            event.timestamp = Date().addingTimeInterval(TimeInterval(i))
        }
        
        let recentEvents = persistenceController.fetchRecentTowerEvents(limit: 3)
        
        XCTAssertEqual(recentEvents.count, 3)
        // Should be in reverse chronological order
        XCTAssertTrue(recentEvents[0].timestamp! > recentEvents[1].timestamp!)
    }
    
    // MARK: - Statistics Tests
    
    func testCalculateStatistics() {
        // Create test data
        let session1 = persistenceController.createSession()
        session1.startTime = Date().addingTimeInterval(-3600) // 1 hour ago
        session1.endTime = Date().addingTimeInterval(-1800) // 30 minutes ago
        
        _ = persistenceController.createTowerEvent(session: session1, towerType: .princess, isPlayerTower: false)
        _ = persistenceController.createTowerEvent(session: session1, towerType: .king, isPlayerTower: true)
        
        let session2 = persistenceController.createSession()
        session2.startTime = Date().addingTimeInterval(-1800) // 30 minutes ago
        session2.endTime = Date() // Just ended
        
        _ = persistenceController.createTowerEvent(session: session2, towerType: .princess, isPlayerTower: false)
        
        let stats = persistenceController.calculateStatistics(for: .day)
        
        XCTAssertEqual(stats.totalSessions, 2)
        XCTAssertEqual(stats.enemyTowersDestroyed, 2)
        XCTAssertEqual(stats.playerTowersLost, 1)
        XCTAssertEqual(Int(stats.totalPlayTime), 3600) // 1 hour total
    }
    
    // MARK: - Data Management Tests
    
    func testDeleteAllData() {
        // Create test data
        let session = persistenceController.createSession()
        _ = persistenceController.createTowerEvent(session: session, towerType: .princess, isPlayerTower: false)
        
        // Verify data exists
        XCTAssertEqual(persistenceController.fetchActiveSessions().count, 1)
        XCTAssertEqual(persistenceController.fetchRecentTowerEvents().count, 1)
        
        // Delete all data
        persistenceController.deleteAllData()
        
        // Verify data is gone
        XCTAssertEqual(persistenceController.fetchActiveSessions().count, 0)
        XCTAssertEqual(persistenceController.fetchRecentTowerEvents().count, 0)
    }
    
    // MARK: - Performance Tests
    
    func testCreateManyEventsPerformance() {
        let session = persistenceController.createSession()
        
        measure {
            for i in 0..<100 {
                _ = persistenceController.createTowerEvent(
                    session: session,
                    towerType: i % 2 == 0 ? .princess : .king,
                    isPlayerTower: i % 3 == 0
                )
            }
        }
        
        XCTAssertEqual(persistenceController.fetchRecentTowerEvents().count, 100)
    }
    
    func testFetchPerformance() {
        let session = persistenceController.createSession()
        
        // Create test data
        for i in 0..<1000 {
            _ = persistenceController.createTowerEvent(
                session: session,
                towerType: .princess,
                isPlayerTower: i % 2 == 0
            )
        }
        
        measure {
            _ = persistenceController.fetchRecentTowerEvents(limit: 50)
        }
    }
}