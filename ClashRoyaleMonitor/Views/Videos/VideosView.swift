import SwiftUI
import AVKit

struct VideosView: View {
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
                        Text("No Tower Fall Videos")
                            .font(.title2)
                            .foregroundColor(.gray)
                        Text("Videos will appear here when tower events are detected during gameplay")
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
            .navigationTitle("Tower Fall Videos")
            .toolbar {
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
        return "Tower Fall - \(formatter.string(from: createdDate))"
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
        
        let videosURL = containerURL.appendingPathComponent("TowerFallClips")
        
        guard FileManager.default.fileExists(atPath: videosURL.path) else {
            print("📁 TowerFallClips directory doesn't exist yet")
            return []
        }
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: videosURL,
                includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                options: .skipsHiddenFiles
            )
            
            let videoFiles = fileURLs.compactMap { url -> VideoFile? in
                guard url.pathExtension.lowercased() == "mp4" else { return nil }
                
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
            print("❌ Error reading TowerFallClips directory: \(error)")
            return []
        }
    }
}

#Preview {
    VideosView()
}