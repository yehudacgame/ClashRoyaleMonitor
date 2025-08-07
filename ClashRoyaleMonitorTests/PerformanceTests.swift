import XCTest
@testable import ClashRoyaleMonitor

class PerformanceTests: XCTestCase {
    
    // MARK: - Memory Tests
    
    func testMemoryUsageUnderLoad() {
        let towerDetector = TowerDetector()
        let testText = [
            "Tower Destroyed",
            "Enemy Tower",
            "Princess Tower",
            "Victory",
            "Crown",
            "Battle",
            "Elixir",
            "Card Played"
        ]
        
        measure {
            autoreleasepool {
                for _ in 0..<10000 {
                    _ = towerDetector.detectTowerEvent(from: testText)
                }
            }
        }
    }
    
    func testCoreDataPerformance() {
        let persistenceController = PersistenceController(inMemory: true)
        
        measure {
            let session = persistenceController.createSession()
            
            for i in 0..<1000 {
                _ = persistenceController.createTowerEvent(
                    session: session,
                    towerType: i % 2 == 0 ? .princess : .king,
                    isPlayerTower: i % 3 == 0
                )
            }
        }
    }
    
    // MARK: - Vision Processing Simulation
    
    func testTextRecognitionSimulation() {
        // Simulate text recognition processing
        let sampleTexts = [
            ["Tower Destroyed", "Enemy", "Princess"],
            ["King Tower", "Victory", "Crown"],
            ["Battle Started", "Elixir", "Cards"],
            ["Tower Down", "Player", "Red Team"],
            ["Destroyed", "Blue Tower", "Arena"]
        ]
        
        let towerDetector = TowerDetector()
        
        measure {
            for text in sampleTexts {
                for _ in 0..<200 { // Simulate 200 frames per text sample
                    _ = towerDetector.detectTowerEvent(from: text)
                }
            }
        }
    }
    
    // MARK: - Statistics Calculation Performance
    
    func testStatisticsCalculationPerformance() {
        let persistenceController = PersistenceController(inMemory: true)
        
        // Create large dataset
        for sessionIndex in 0..<100 {
            let session = persistenceController.createSession()
            session.startTime = Date().addingTimeInterval(TimeInterval(-sessionIndex * 3600))
            session.endTime = session.startTime?.addingTimeInterval(1800)
            
            for _ in 0..<Int.random(in: 1...10) {
                _ = persistenceController.createTowerEvent(
                    session: session,
                    towerType: [.king, .princess].randomElement()!,
                    isPlayerTower: Bool.random()
                )
            }
        }
        
        measure {
            _ = persistenceController.calculateStatistics(for: .all)
        }
    }
    
    // MARK: - App Launch Simulation
    
    func testAppLaunchPerformance() {
        measure {
            // Simulate app launch operations
            let persistenceController = PersistenceController(inMemory: true)
            let _ = NotificationManager()
            let _ = AppState()
            
            // Load initial data
            _ = persistenceController.fetchActiveSessions()
            _ = persistenceController.fetchRecentTowerEvents(limit: 10)
        }
    }
    
    // MARK: - Concurrent Operations
    
    func testConcurrentDataAccess() {
        let persistenceController = PersistenceController(inMemory: true)
        let session = persistenceController.createSession()
        
        measure {
            let group = DispatchGroup()
            
            // Simulate concurrent read/write operations
            for _ in 0..<10 {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    for _ in 0..<50 {
                        _ = persistenceController.createTowerEvent(
                            session: session,
                            towerType: .princess,
                            isPlayerTower: Bool.random()
                        )
                    }
                    group.leave()
                }
            }
            
            for _ in 0..<5 {
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    _ = persistenceController.fetchRecentTowerEvents(limit: 20)
                    group.leave()
                }
            }
            
            group.wait()
        }
    }
}