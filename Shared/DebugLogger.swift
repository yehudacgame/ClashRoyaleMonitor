import Foundation

/// Shared debug logger for communication between extension and main app
class DebugLogger {
    static let shared = DebugLogger()
    
    private let maxLogEntries = 1000
    private let logFileName = "debug_logs.json"
    private let queue = DispatchQueue(label: "com.clashmonitor.debuglogger", attributes: .concurrent)
    
    private var appGroupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.clashmonitor.shared2")
    }
    
    // MARK: - Models
    
    struct LogEntry: Codable {
        let id: String
        let timestamp: Date
        let level: LogLevel
        let source: LogSource
        let category: LogCategory
        let message: String
        let data: [String: String]?
        
        init(level: LogLevel, source: LogSource, category: LogCategory, message: String, data: [String: String]? = nil) {
            self.id = UUID().uuidString
            self.timestamp = Date()
            self.level = level
            self.source = source
            self.category = category
            self.message = message
            self.data = data
        }
    }
    
    enum LogLevel: String, Codable {
        case debug = "debug"
        case info = "info"
        case warning = "warning"
        case error = "error"
    }
    
    enum LogSource: String, Codable {
        case mainApp = "main"
        case extension = "extension"
        case webUI = "web"
    }
    
    enum LogCategory: String, Codable {
        case general = "general"
        case ocr = "ocr"
        case towerDetection = "tower"
        case video = "video"
        case authenticity = "auth"
        case performance = "perf"
    }
    
    // MARK: - Public Methods
    
    /// Log a general message
    func log(_ message: String, level: LogLevel = .info, source: LogSource = .extension, category: LogCategory = .general, data: [String: String]? = nil) {
        let entry = LogEntry(level: level, source: source, category: category, message: message, data: data)
        appendLog(entry)
    }
    
    /// Log OCR results with detailed data
    func logOCR(texts: [String], frameNumber: Int, processingTime: TimeInterval? = nil) {
        var data: [String: String] = [
            "frameNumber": "\(frameNumber)",
            "textCount": "\(texts.count)",
            "texts": texts.prefix(10).joined(separator: " | ")
        ]
        
        if let time = processingTime {
            data["processingMs"] = String(format: "%.1f", time * 1000)
        }
        
        log("OCR Results - Frame \(frameNumber) (\(texts.count) texts detected)",
            level: .debug,
            source: .extension,
            category: .ocr,
            data: data)
    }
    
    /// Log tower detection events
    func logTowerEvent(towerType: String, isPlayerTower: Bool, frameNumber: Int, confidence: Float? = nil) {
        var data: [String: String] = [
            "towerType": towerType,
            "owner": isPlayerTower ? "Player" : "Enemy",
            "frame": "\(frameNumber)"
        ]
        
        if let conf = confidence {
            data["confidence"] = String(format: "%.2f", conf)
        }
        
        log("🎯 Tower Event Detected: \(towerType)",
            level: .warning,
            source: .extension,
            category: .towerDetection,
            data: data)
    }
    
    /// Log authenticity validation results
    func logAuthenticity(isAuthentic: Bool, confidence: Float, reason: String, frameNumber: Int) {
        let data: [String: String] = [
            "isAuthentic": "\(isAuthentic)",
            "confidence": String(format: "%.2f%%", confidence * 100),
            "reason": reason,
            "frame": "\(frameNumber)"
        ]
        
        log(isAuthentic ? "✅ Authentic gameplay" : "🚨 Suspicious content detected",
            level: isAuthentic ? .info : .error,
            source: .extension,
            category: .authenticity,
            data: data)
    }
    
    /// Log performance metrics
    func logPerformance(metric: String, value: Double, unit: String = "ms") {
        log("Performance: \(metric)",
            level: .debug,
            source: .extension,
            category: .performance,
            data: [
                "metric": metric,
                "value": String(format: "%.2f", value),
                "unit": unit
            ])
    }
    
    /// Log video buffer events
    func logVideo(event: String, details: [String: String]? = nil) {
        log("Video: \(event)",
            level: .info,
            source: .extension,
            category: .video,
            data: details)
    }
    
    // MARK: - File Operations
    
    private func appendLog(_ entry: LogEntry) {
        queue.async(flags: .barrier) {
            guard let logURL = self.appGroupURL?.appendingPathComponent(self.logFileName) else { return }
            
            var logs = self.readLogsInternal()
            logs.append(entry)
            
            // Keep only recent logs
            if logs.count > self.maxLogEntries {
                logs = Array(logs.suffix(self.maxLogEntries))
            }
            
            // Write to file
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(logs)
                try data.write(to: logURL, options: .atomic)
            } catch {
                print("❌ DebugLogger: Failed to write logs: \(error)")
            }
        }
    }
    
    /// Read all logs (thread-safe)
    func readLogs() -> [LogEntry] {
        queue.sync {
            readLogsInternal()
        }
    }
    
    /// Read logs after a specific timestamp
    func readLogs(after timestamp: Date) -> [LogEntry] {
        queue.sync {
            readLogsInternal().filter { $0.timestamp > timestamp }
        }
    }
    
    /// Read logs by category
    func readLogs(category: LogCategory) -> [LogEntry] {
        queue.sync {
            readLogsInternal().filter { $0.category == category }
        }
    }
    
    private func readLogsInternal() -> [LogEntry] {
        guard let logURL = appGroupURL?.appendingPathComponent(logFileName),
              let data = try? Data(contentsOf: logURL) else {
            return []
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([LogEntry].self, from: data)
        } catch {
            print("❌ DebugLogger: Failed to decode logs: \(error)")
            return []
        }
    }
    
    /// Clear all logs
    func clearLogs() {
        queue.async(flags: .barrier) {
            guard let logURL = self.appGroupURL?.appendingPathComponent(self.logFileName) else { return }
            try? FileManager.default.removeItem(at: logURL)
        }
    }
    
    /// Get log statistics
    func getStats() -> LogStats {
        let logs = readLogs()
        
        var stats = LogStats()
        stats.totalLogs = logs.count
        
        for log in logs {
            // Count by category
            switch log.category {
            case .ocr:
                stats.ocrCount += 1
            case .towerDetection:
                stats.towerEvents += 1
            case .authenticity:
                stats.authChecks += 1
                if log.level == .error {
                    stats.fraudDetections += 1
                }
            case .performance:
                stats.perfLogs += 1
            case .video:
                stats.videoEvents += 1
            default:
                break
            }
            
            // Count by level
            switch log.level {
            case .error:
                stats.errors += 1
            case .warning:
                stats.warnings += 1
            default:
                break
            }
        }
        
        return stats
    }
    
    struct LogStats {
        var totalLogs = 0
        var ocrCount = 0
        var towerEvents = 0
        var authChecks = 0
        var fraudDetections = 0
        var videoEvents = 0
        var perfLogs = 0
        var errors = 0
        var warnings = 0
    }
}

// MARK: - Convenience Extensions

extension DebugLogger {
    /// Quick debug logging
    func debug(_ message: String, data: [String: String]? = nil) {
        log(message, level: .debug, data: data)
    }
    
    /// Quick info logging
    func info(_ message: String, data: [String: String]? = nil) {
        log(message, level: .info, data: data)
    }
    
    /// Quick warning logging
    func warning(_ message: String, data: [String: String]? = nil) {
        log(message, level: .warning, data: data)
    }
    
    /// Quick error logging
    func error(_ message: String, data: [String: String]? = nil) {
        log(message, level: .error, data: data)
    }
}