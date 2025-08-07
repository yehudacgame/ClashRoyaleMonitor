import XCTest
@testable import ClashRoyaleMonitor

class IntegrationTests: XCTestCase {
    var persistenceController: PersistenceController!
    var notificationManager: NotificationManager!
    var appState: AppState!
    
    override func setUp() {
        super.setUp()
        persistenceController = PersistenceController(inMemory: true)
        notificationManager = NotificationManager()
        appState = AppState()
    }
    
    override func tearDown() {
        persistenceController = nil
        notificationManager = nil
        appState = nil
        super.tearDown()
    }
    
    // MARK: - End-to-End Workflow Tests
    
    func testCompleteGameSessionWorkflow() {
        // 1. Start new session
        let session = persistenceController.createSession()
        XCTAssertNotNil(session.id)
        XCTAssertNotNil(session.startTime)
        
        // 2. Simulate tower destruction events
        let event1 = persistenceController.createTowerEvent(
            session: session,
            towerType: .princess,
            isPlayerTower: false
        )
        
        let event2 = persistenceController.createTowerEvent(
            session: session,
            towerType: .king,
            isPlayerTower: true
        )
        
        // 3. Verify session stats are updated
        XCTAssertEqual(session.enemyTowersDestroyed, 1)
        XCTAssertEqual(session.playerTowersLost, 1)
        
        // 4. End session
        persistenceController.endSession(session)
        XCTAssertNotNil(session.endTime)
        
        // 5. Verify statistics
        let stats = persistenceController.calculateStatistics(for: .all)
        XCTAssertEqual(stats.totalSessions, 1)
        XCTAssertEqual(stats.enemyTowersDestroyed, 1)
        XCTAssertEqual(stats.playerTowersLost, 1)
        
        // 6. Verify events are retrievable
        let recentEvents = persistenceController.fetchRecentTowerEvents()
        XCTAssertEqual(recentEvents.count, 2)
    }
    
    func testMultipleSessionsWorkflow() {
        // Create multiple sessions with different outcomes
        for i in 0..<5 {
            let session = persistenceController.createSession()
            session.startTime = Date().addingTimeInterval(TimeInterval(-i * 3600))
            
            // Vary the number of tower events per session
            let eventCount = Int.random(in: 1...6)
            for j in 0..<eventCount {
                _ = persistenceController.createTowerEvent(
                    session: session,
                    towerType: j % 2 == 0 ? .princess : .king,
                    isPlayerTower: j % 3 == 0
                )
            }
            
            persistenceController.endSession(session)
        }
        
        // Verify all sessions are stored
        let allSessions = persistenceController.fetchSessions()
        XCTAssertEqual(allSessions.count, 5)
        
        // Verify statistics calculation
        let stats = persistenceController.calculateStatistics(for: .all)
        XCTAssertEqual(stats.totalSessions, 5)
        XCTAssertTrue(stats.enemyTowersDestroyed > 0)
        XCTAssertTrue(stats.playerTowersLost >= 0)
    }
    
    // MARK: - Data Consistency Tests
    
    func testDataConsistencyAcrossOperations() {
        let session = persistenceController.createSession()
        
        // Create events in rapid succession
        var expectedEnemyTowers = 0
        var expectedPlayerTowers = 0
        
        for i in 0..<20 {
            let isPlayerTower = i % 4 == 0 // Every 4th event is player tower
            
            _ = persistenceController.createTowerEvent(
                session: session,
                towerType: .princess,
                isPlayerTower: isPlayerTower
            )
            
            if isPlayerTower {
                expectedPlayerTowers += 1
            } else {
                expectedEnemyTowers += 1
            }
        }
        
        // Verify session counters match expectations
        XCTAssertEqual(Int(session.enemyTowersDestroyed), expectedEnemyTowers)
        XCTAssertEqual(Int(session.playerTowersLost), expectedPlayerTowers)
        
        // Verify event count matches
        let events = persistenceController.fetchRecentTowerEvents()
        let sessionEvents = events.filter { $0.session?.id == session.id }
        XCTAssertEqual(sessionEvents.count, 20)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorRecovery() {
        // Test recovery from various error conditions
        
        // 1. Try to create event with invalid session (should not crash)
        let invalidSession = SessionEntity(context: persistenceController.container.viewContext)
        invalidSession.id = UUID()
        
        // This should not crash the app
        let event = persistenceController.createTowerEvent(
            session: invalidSession,
            towerType: .princess,
            isPlayerTower: false
        )
        
        XCTAssertNotNil(event)
    }
    
    // MARK: - Memory Management Tests
    
    func testMemoryManagementUnderLoad() {
        // Create and cleanup many objects to test memory management
        for batchIndex in 0..<10 {
            autoreleasepool {
                let session = persistenceController.createSession()
                
                for eventIndex in 0..<100 {
                    _ = persistenceController.createTowerEvent(
                        session: session,
                        towerType: .princess,
                        isPlayerTower: eventIndex % 2 == 0
                    )
                }
                
                persistenceController.endSession(session)
            }
        }
        
        // Verify data integrity after high-volume operations
        let allSessions = persistenceController.fetchSessions()
        XCTAssertEqual(allSessions.count, 10)
        
        let allEvents = persistenceController.fetchRecentTowerEvents()
        XCTAssertEqual(allEvents.count, 1000)
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentAccess() {
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 20
        
        let session = persistenceController.createSession()
        
        // Launch multiple concurrent operations
        for i in 0..<20 {
            DispatchQueue.global(qos: .userInitiated).async {
                // Each thread creates events
                for j in 0..<10 {
                    _ = self.persistenceController.createTowerEvent(
                        session: session,
                        towerType: .princess,
                        isPlayerTower: (i + j) % 2 == 0
                    )
                }
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: 10.0)
        
        // Verify all events were created successfully
        let events = persistenceController.fetchRecentTowerEvents()
        XCTAssertEqual(events.count, 200)
        
        // Verify session counters are correct
        let expectedTotal = Int(session.enemyTowersDestroyed + session.playerTowersLost)
        XCTAssertEqual(expectedTotal, 200)
    }
    
    // MARK: - App State Integration Tests
    
    func testAppStateIntegration() {
        // Test app state management
        XCTAssertFalse(appState.isMonitoring)
        XCTAssertEqual(appState.currentTab, 0)
        
        // Simulate monitoring state changes
        appState.isMonitoring = true
        XCTAssertTrue(appState.isMonitoring)
        
        // Test broadcast status checking
        appState.checkBroadcastStatus()
        
        // Since no actual broadcast is running, should remain false
        // (In real testing, we would mock the UserDefaults)
    }
}