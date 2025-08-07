import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingVideos = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("🔫 COD KILL MONITOR 🔫")
                    .font(.title)
                    .foregroundColor(.red)
                    .padding()
                
                Text("Automatically saves your kill highlights!")
                    .font(.headline)
                    .padding()
                
                Button(action: {
                    openDocumentsFolder()
                }) {
                    HStack {
                        Image(systemName: "folder.fill")
                        Text("Open Documents Folder")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
                
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
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
                
                Text("Kill highlights saved to:")
                    .font(.headline)
                    .padding(.top)
                
                Text("Documents folder as COD_Kill_*.mp4")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                
                Spacer()
            }
            .navigationTitle("COD Kill Monitor")
        }
        .sheet(isPresented: $showingVideos) {
            VideoListView()
        }
    }
    
    private func openDocumentsFolder() {
        // This will open the Files app to the Documents folder
        if let url = URL(string: "shareddocuments://") {
            UIApplication.shared.open(url)
        }
    }
}

struct VideoListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var videoFiles: [URL] = []
    
    var body: some View {
        NavigationView {
            VStack {
                if videoFiles.isEmpty {
                    Text("No kill highlights found")
                        .foregroundColor(.secondary)
                        .padding()
                    
                    Text("Highlights are saved to:")
                        .font(.headline)
                        .padding(.top)
                    
                    Text("Documents folder as COD_Kill_*.mp4")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    List(videoFiles, id: \.self) { url in
                        VStack(alignment: .leading) {
                            Text(url.lastPathComponent)
                                .font(.headline)
                            Text(url.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Kill Highlights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            loadVideoFiles()
        }
    }
    
    private func loadVideoFiles() {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            videoFiles = files.filter { 
                $0.pathExtension == "mp4" && $0.lastPathComponent.starts(with: "COD_Kill_")
            }
        } catch {
            print("Error loading video files: \(error)")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(NotificationManager())
}