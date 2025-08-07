import Foundation
import SwiftUI

// MARK: - Statistics Models
struct OverallStats {
    var totalSessions: Int = 0
    var totalPlayTime: TimeInterval = 0
    var enemyTowersDestroyed: Int = 0
    var playerTowersLost: Int = 0
}

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let enemyTowers: Int
    let playerTowers: Int
}

// MARK: - Statistics View Model
class StatisticsViewModel: ObservableObject {
    @Published var overallStats = OverallStats()
    @Published var chartData: [ChartDataPoint] = []
    @Published var recentSessions: [SessionEntity] = []
    
    private let persistenceController = PersistenceController.shared
    
    func loadStats(for timeRange: StatisticsView.TimeRange) {
        overallStats = persistenceController.calculateStatistics(for: timeRange)
        let sessions = fetchSessionsForTimeRange(timeRange)
        generateChartData(from: sessions)
        recentSessions = Array(sessions.prefix(10))
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
        
        return persistenceController.fetchSessions(from: startDate, to: now)
    }
    
    private func generateChartData(from sessions: [SessionEntity]) {
        let calendar = Calendar.current
        var dailyData: [Date: (enemy: Int, player: Int)] = [:]
        
        for session in sessions {
            guard let startTime = session.startTime else { continue }
            let day = calendar.startOfDay(for: startTime)
            let existing = dailyData[day] ?? (0, 0)
            dailyData[day] = (
                existing.enemy + Int(session.enemyTowersDestroyed),
                existing.player + Int(session.playerTowersLost)
            )
        }
        
        chartData = dailyData.map { date, towers in
            ChartDataPoint(
                date: date,
                enemyTowers: towers.enemy,
                playerTowers: towers.player
            )
        }.sorted { $0.date < $1.date }
    }
    
    func exportStats() {
        let csvContent = generateCSV()
        
        // Create activity controller to share CSV
        guard let data = csvContent.data(using: .utf8) else { return }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("clash_royale_stats.csv")
        try? data.write(to: tempURL)
        
        let activityVC = UIActivityViewController(
            activityItems: [tempURL],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
    
    private func generateCSV() -> String {
        var csv = "Date,Duration (min),Enemy Towers,Player Towers\n"
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .short
        
        for session in recentSessions {
            guard let startTime = session.startTime else { continue }
            let duration = Int(session.endTime?.timeIntervalSince(startTime) ?? 0) / 60
            csv += "\(dateFormatter.string(from: startTime)),\(duration),\(session.enemyTowersDestroyed),\(session.playerTowersLost)\n"
        }
        
        return csv
    }
    
}