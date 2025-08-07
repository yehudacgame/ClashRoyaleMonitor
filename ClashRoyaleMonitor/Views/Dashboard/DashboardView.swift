import SwiftUI
import ReplayKit
import AVKit

struct DashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showingBroadcastPicker = false
    @State private var showingVideos = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Monitoring Status Card
                    MonitoringStatusCard(isMonitoring: appState.isMonitoring)
                        .padding(.horizontal)
                    
                    // Quick Actions
                    VStack(spacing: 12) {
                        // Launch Call of Duty Button
                        Button(action: viewModel.launchCallOfDuty) {
                            HStack {
                                Image(systemName: "gamecontroller.fill")
                                Text("Launch Call of Duty Mobile")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        // Start/Stop Monitoring Button
                        Button(action: {
                            if appState.isMonitoring {
                                viewModel.stopMonitoring()
                            } else {
                                showingBroadcastPicker = true
                            }
                        }) {
                            HStack {
                                Image(systemName: appState.isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                                Text(appState.isMonitoring ? "Stop Monitoring" : "Start Monitoring")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(appState.isMonitoring ? Color.red : Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        // View Videos Button
                        Button(action: {
                            showingVideos = true
                        }) {
                            HStack {
                                Image(systemName: "video.fill")
                                Text("View Kill Highlights")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    // Current Session Stats
                    if let session = viewModel.currentSession {
                        CurrentSessionCard(session: session)
                            .padding(.horizontal)
                    }
                    
                    // Recent Kill Events
                    if !viewModel.recentEvents.isEmpty {
                        RecentEventsCard(events: viewModel.recentEvents)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("COD Kill Monitor")
            .sheet(isPresented: $showingBroadcastPicker) {
                BroadcastPickerView { started in
                    if started {
                        appState.isMonitoring = true
                        viewModel.startNewSession()
                    }
                    showingBroadcastPicker = false
                }
            }
            .sheet(isPresented: $showingVideos) {
                KillHighlightsView()
            }
            .onAppear {
                viewModel.loadCurrentSession()
            }
        }
    }
}

// MARK: - Monitoring Status Card
struct MonitoringStatusCard: View {
    let isMonitoring: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(isMonitoring ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(isMonitoring ? "Monitoring Active" : "Monitoring Inactive")
                    .font(.headline)
                
                Spacer()
                
                Image(systemName: isMonitoring ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                    .foregroundColor(isMonitoring ? .green : .gray)
            }
            
            if isMonitoring {
                Text("Watching for kill events...")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Current Session Card
struct CurrentSessionCard: View {
    let session: SessionEntity
    @State private var timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var duration: TimeInterval = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Current Session")
                .font(.headline)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDuration(duration))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                VStack {
                    Text("Kills")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(session.enemyTowersDestroyed)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                }
                
                VStack {
                    Text("Deaths")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(session.playerTowersLost)")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .onReceive(timer) { _ in
            if let startTime = session.startTime {
                duration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Recent Events Card
struct RecentEventsCard: View {
    let events: [TowerEventEntity]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Events")
                .font(.headline)
            
            ForEach(events.prefix(5)) { event in
                HStack {
                    Image(systemName: event.isPlayerTower ? "shield.slash.fill" : "shield.checkered")
                        .foregroundColor(event.isPlayerTower ? .red : .green)
                    
                    VStack(alignment: .leading) {
                        let towerType = TowerEvent.TowerType(rawValue: event.towerType ?? "") ?? .unknown
                        Text("\(event.isPlayerTower ? "Lost" : "Destroyed") \(towerType.displayName)")
                            .font(.subheadline)
                        if let timestamp = event.timestamp {
                            Text(timestamp, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// MARK: - Kill Highlights View
struct KillHighlightsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var videoFiles: [VideoFile] = []
    @State private var isLoading = true
    @State private var selectedVideo: VideoFile?
    @State private var showingVideoPlayer = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading videos...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if videoFiles.isEmpty {
                    VStack {
                        Image(systemName: "video.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No Kill Highlights")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Videos will appear here when kills are detected during gameplay")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(videoFiles) { video in
                        VideoRowView(video: video) {
                            selectedVideo = video
                            showingVideoPlayer = true
                        }
                    }
                }
            }
            .navigationTitle("Kill Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        loadVideos()
                    }
                }
            }
            .onAppear {
                loadVideos()
            }
            .sheet(isPresented: $showingVideoPlayer) {
                if let video = selectedVideo {
                    VideoPlayerView(video: video)
                }
            }
        }
    }
    
    private func loadVideos() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            let videos = VideoFileManager.shared.loadVideoFiles()
            
            DispatchQueue.main.async {
                self.videoFiles = videos.sorted { $0.createdDate > $1.createdDate }
                self.isLoading = false
            }
        }
    }
}

struct VideoRowView: View {
    let video: VideoFile
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(video.displayName)
                    .font(.headline)
                Text(video.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(video.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: onTap) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Play")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
    }
}

struct VideoPlayerView: View {
    let video: VideoFile
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    
    var body: some View {
        NavigationView {
            VStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    ProgressView("Loading video...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(video.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    ShareLink(item: video.url) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            player = AVPlayer(url: video.url)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
}

// MARK: - Data Models

struct VideoFile: Identifiable {
    let id = UUID()
    let url: URL
    let createdDate: Date
    let fileSize: Int64
    
    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return "COD Kill - \(formatter.string(from: createdDate))"
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdDate)
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - Video File Manager

class VideoFileManager {
    static let shared = VideoFileManager()
    
    private init() {}
    
    func loadVideoFiles() -> [VideoFile] {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.clashmonitor.shared2"
        ) else {
            print("❌ Failed to get app group container URL")
            return []
        }
        
        let videosURL = containerURL.appendingPathComponent("Documents")
        
        guard FileManager.default.fileExists(atPath: videosURL.path) else {
            print("📁 Documents directory doesn't exist yet")
            return []
        }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: videosURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            
            let videoFiles = fileURLs.compactMap { url -> VideoFile? in
                guard url.pathExtension.lowercased() == "mp4" && url.lastPathComponent.starts(with: "COD_Kill_") else { return nil }
                
                do {
                    let resourceValues = try url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
                    let createdDate = resourceValues.creationDate ?? Date()
                    let fileSize = Int64(resourceValues.fileSize ?? 0)
                    
                    return VideoFile(
                        url: url,
                        createdDate: createdDate,
                        fileSize: fileSize
                    )
                } catch {
                    print("❌ Error getting file attributes for \(url): \(error)")
                    return nil
                }
            }
            
            print("📹 Found \(videoFiles.count) video files")
            return videoFiles
            
        } catch {
            print("❌ Error reading Documents directory: \(error)")
            return []
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
        .environmentObject(NotificationManager())
}