import XCTest
@testable import ClashRoyaleMonitor

class TowerDetectorTests: XCTestCase {
    var towerDetector: TowerDetector!
    
    override func setUp() {
        super.setUp()
        towerDetector = TowerDetector()
    }
    
    override func tearDown() {
        towerDetector = nil
        super.tearDown()
    }
    
    // MARK: - Tower Detection Tests
    
    func testDetectEnemyTowerDestruction() {
        let recognizedText = [
            "Tower Destroyed",
            "Enemy Tower",
            "Princess Tower",
            "Blue Team"
        ]
        
        let event = towerDetector.detectTowerEvent(from: recognizedText)
        
        XCTAssertNotNil(event)
        XCTAssertFalse(event!.isPlayerTower)
        XCTAssertEqual(event!.towerType, .princess)
    }
    
    func testDetectPlayerTowerDestruction() {
        let recognizedText = [
            "Tower Destroyed",
            "Your Tower",
            "King Tower",
            "Red Team"
        ]
        
        let event = towerDetector.detectTowerEvent(from: recognizedText)
        
        XCTAssertNotNil(event)
        XCTAssertTrue(event!.isPlayerTower)
        XCTAssertEqual(event!.towerType, .king)
    }
    
    func testNoDetectionWithoutKeywords() {
        let recognizedText = [
            "Elixir",
            "Card Played",
            "Battle Started"
        ]
        
        let event = towerDetector.detectTowerEvent(from: recognizedText)
        
        XCTAssertNil(event)
    }
    
    func testCooldownPreventsSpam() {
        let recognizedText = [
            "Tower Destroyed",
            "Enemy Tower"
        ]
        
        // First detection should work
        let event1 = towerDetector.detectTowerEvent(from: recognizedText)
        XCTAssertNotNil(event1)
        
        // Immediate second detection should be nil due to cooldown
        let event2 = towerDetector.detectTowerEvent(from: recognizedText)
        XCTAssertNil(event2)
    }
    
    func testDetectKingTower() {
        let recognizedText = [
            "Destroyed",
            "King Tower",
            "Victory"
        ]
        
        let event = towerDetector.detectTowerEvent(from: recognizedText)
        
        XCTAssertNotNil(event)
        XCTAssertEqual(event!.towerType, .king)
    }
    
    func testDetectPrincessTower() {
        let recognizedText = [
            "Tower down",
            "Princess Tower",
            "Arena"
        ]
        
        let event = towerDetector.detectTowerEvent(from: recognizedText)
        
        XCTAssertNotNil(event)
        XCTAssertEqual(event!.towerType, .princess)
    }
    
    func testDetectUnknownTowerType() {
        let recognizedText = [
            "Tower Destroyed",
            "Some Tower"
        ]
        
        let event = towerDetector.detectTowerEvent(from: recognizedText)
        
        XCTAssertNotNil(event)
        XCTAssertEqual(event!.towerType, .unknown)
    }
    
    // MARK: - Performance Tests
    
    func testDetectionPerformance() {
        let recognizedText = [
            "Tower Destroyed",
            "Enemy Tower",
            "Princess Tower",
            "Blue Team",
            "Victory",
            "Crown"
        ]
        
        measure {
            for _ in 0..<1000 {
                _ = towerDetector.detectTowerEvent(from: recognizedText)
            }
        }
    }
}