import Foundation
import CoreData

@objc(SessionEntity)
public class SessionEntity: NSManagedObject {
    
    // Convert to GameSession model
    func toGameSession() -> GameSession {
        var session = GameSession(startTime: startTime ?? Date())
        session.endTime = endTime
        session.playerTowersLost = Int(playerTowersLost)
        session.enemyTowersDestroyed = Int(enemyTowersDestroyed)
        return session
    }
    
    // Update from GameSession model
    func update(from session: GameSession) {
        self.startTime = session.startTime
        self.endTime = session.endTime
        self.playerTowersLost = Int16(session.playerTowersLost)
        self.enemyTowersDestroyed = Int16(session.enemyTowersDestroyed)
    }
}