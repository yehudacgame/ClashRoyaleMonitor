import SwiftUI
import Charts

struct StatisticsView: View {
    @StateObject private var viewModel = StatisticsViewModel()
    @State private var selectedTimeRange = TimeRange.week
    
    enum TimeRange: String, CaseIterable {
        case day = "Day"
        case week = "Week"
        case month = "Month"
        case all = "All Time"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Time Range Picker
                    Picker("Time Range", selection: $selectedTimeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Overall Stats
                    OverallStatsCard(stats: viewModel.overallStats)
                        .padding(.horizontal)
                    
                    // Tower Destruction Chart
                    if !viewModel.chartData.isEmpty {
                        TowerChartCard(data: viewModel.chartData)
                            .padding(.horizontal)
                    }
                    
                    // Recent Sessions
                    RecentSessionsCard(sessions: viewModel.recentSessions)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Statistics")
            .navigationBarItems(trailing: Button(action: viewModel.exportStats) {
                Image(systemName: "square.and.arrow.up")
            })
            .onAppear {
                viewModel.loadStats(for: selectedTimeRange)
            }
            .onChange(of: selectedTimeRange) { _ in
                viewModel.loadStats(for: selectedTimeRange)
            }
        }
    }
}

// MARK: - Overall Stats Card
struct OverallStatsCard: View {
    let stats: OverallStats
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Overall Performance")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack(spacing: 20) {
                StatItem(
                    title: "Total Sessions",
                    value: "\(stats.totalSessions)",
                    systemImage: "gamecontroller.fill"
                )
                
                StatItem(
                    title: "Play Time",
                    value: formatDuration(stats.totalPlayTime),
                    systemImage: "clock.fill"
                )
            }
            
            HStack(spacing: 20) {
                StatItem(
                    title: "Towers Destroyed",
                    value: "\(stats.enemyTowersDestroyed)",
                    systemImage: "shield.checkered",
                    color: .green
                )
                
                StatItem(
                    title: "Towers Lost",
                    value: "\(stats.playerTowersLost)",
                    systemImage: "shield.slash.fill",
                    color: .red
                )
            }
            
            // Win Rate Estimation
            if stats.totalSessions > 0 {
                let winRate = Double(stats.enemyTowersDestroyed) / Double(stats.enemyTowersDestroyed + stats.playerTowersLost) * 100
                
                HStack {
                    Text("Estimated Win Rate")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(String(format: "%.1f%%", winRate))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(winRate >= 50 ? .green : .red)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Stat Item
struct StatItem: View {
    let title: String
    let value: String
    let systemImage: String
    var color: Color = .blue
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Tower Chart Card
struct TowerChartCard: View {
    let data: [ChartDataPoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tower Destruction Trend")
                .font(.headline)
            
            Chart(data) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Enemy Towers", point.enemyTowers)
                )
                .foregroundStyle(.green)
                .symbol(.circle)
                
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Player Towers", point.playerTowers)
                )
                .foregroundStyle(.red)
                .symbol(.circle)
            }
            .frame(height: 200)
            
            HStack(spacing: 20) {
                Label("Enemy Towers", systemImage: "circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                
                Label("Your Towers", systemImage: "circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Recent Sessions Card
struct RecentSessionsCard: View {
    let sessions: [SessionEntity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
            
            if sessions.isEmpty {
                Text("No sessions recorded yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(sessions.prefix(5)) { session in
                    SessionRow(session: session)
                    
                    if session.id != sessions.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Session Row
struct SessionRow: View {
    let session: SessionEntity
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                if let startTime = session.startTime {
                    Text(startTime, style: .date)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(formatDuration(session))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Label("\(session.enemyTowersDestroyed)", systemImage: "shield.checkered")
                    .foregroundColor(.green)
                    .font(.subheadline)
                
                Label("\(session.playerTowersLost)", systemImage: "shield.slash.fill")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
        }
    }
    
    private func formatDuration(_ session: SessionEntity) -> String {
        guard let startTime = session.startTime else { return "0 min" }
        let endTime = session.endTime ?? Date()
        let duration = endTime.timeIntervalSince(startTime)
        let minutes = Int(duration) / 60
        return "\(minutes) min"
    }
}

#Preview {
    StatisticsView()
}