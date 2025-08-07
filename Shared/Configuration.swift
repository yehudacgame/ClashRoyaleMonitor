import Foundation

struct AppConfiguration {
    // App Groups
    static let appGroupID = "group.com.clashmonitor.shared2"
    
    // Kill Detection
    static let killDetectionCooldown: TimeInterval = 2.0
    static let videoSaveCooldown: TimeInterval = 3.0
    static let frameProcessingInterval = 10 // Process every 10th frame
    
    // Video Recording
    static let bufferDuration: TimeInterval = 10.0
    static let videoQuality: Float = 0.8
    
    // App Groups Keys
    static let shouldSaveHighlightKey = "shouldSaveHighlight"
    static let killDetectedAtKey = "killDetectedAt"
    
    // OCR Settings
    static let minimumTextConfidence: Float = 0.6
    static let killKeywords = ["KILL", "ELIMINATED", "ELIMINA"]
}