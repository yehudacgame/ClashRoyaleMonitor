import SwiftUI
import UIKit
import WebKit
import AVKit
import ReplayKit
import CoreData
import Foundation
import AVFoundation
import UserNotifications

@main
struct ClashRoyaleMonitorApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var notificationManager = NotificationManager()
    let persistenceController = PersistenceController.shared
    
    var body: some Scene {
        WindowGroup {
            WebViewWrapper(appState: appState, notificationManager: notificationManager)
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    setupApp()
                }
        }
    }
    
    private func setupApp() {
        // Request notification permissions
        notificationManager.requestAuthorization()
        
        // Check if onboarding is completed
        if !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            // Skip onboarding for development - go straight to main app
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            appState.showOnboarding = false
        }
        
        // Register for app lifecycle notifications
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            appState.checkBroadcastStatus()
        }
        
        // Process any pending sessions when app becomes active
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            // Delay to ensure app is fully active
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("📱 App became active - checking for pending session processing")
                // Check for sessions through the WebViewController if it exists
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let rootViewController = window.rootViewController as? UIHostingController<WebViewWrapper>,
                   let webViewWrapper = rootViewController.rootView as? WebViewWrapper {
                    // Trigger session processing check
                    print("🔄 Triggering session processing check...")
                }
            }
        }
    }
}

// MARK: - WebViewController
class WebViewController: UIViewController {
    private var webView: WKWebView!
    private var appState: AppState
    private var notificationManager: NotificationManager
    
    // App Groups monitoring for extension communication
    private var appGroupDefaults: UserDefaults?
    private var killDetectionTimer: Timer?
    private var hasAutoStarted = false
    
    init(appState: AppState, notificationManager: NotificationManager) {
        self.appState = appState
        self.notificationManager = notificationManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        loadWebUI()
        setupNotificationObservers()
        
        // Initialize video recording system
        setupVideoRecording()
        print("🚀 WebViewController loaded - Video recording system initialized")
    }
    
    private func setupWebView() {
        let configuration = WKWebViewConfiguration()
        
        // Set up message handler for JavaScript communication
        let contentController = WKUserContentController()
        contentController.add(self, name: "iosApp")
        configuration.userContentController = contentController
        
        // Allow inline media playback
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        
        webView = WKWebView(frame: view.bounds, configuration: configuration)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.navigationDelegate = self
        
        // Disable bouncing
        webView.scrollView.bounces = false
        
        view.addSubview(webView)
    }
    
    private func loadWebUI() {
        // Try different paths to find the HTML file
        var htmlPath: String?
        
        // First try with subdirectory
        htmlPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "Resources/WebUI")
        
        // If not found, try without subdirectory
        if htmlPath == nil {
            htmlPath = Bundle.main.path(forResource: "index", ofType: "html")
        }
        
        // If still not found, try in WebUI subdirectory directly
        if htmlPath == nil {
            htmlPath = Bundle.main.path(forResource: "index", ofType: "html", inDirectory: "WebUI")
        }
        
        guard let validHtmlPath = htmlPath else {
            print("❌ Could not find index.html in bundle")
            print("📁 Available resources:")
            if let resourcePath = Bundle.main.resourcePath {
                do {
                    let resources = try FileManager.default.contentsOfDirectory(atPath: resourcePath)
                    for resource in resources.prefix(10) {
                        print("  - \(resource)")
                    }
                } catch {
                    print("  Error listing resources: \(error)")
                }
            }
            return
        }
        
        print("✅ Found HTML file at: \(validHtmlPath)")
        let htmlUrl = URL(fileURLWithPath: validHtmlPath)
        let htmlDirectory = htmlUrl.deletingLastPathComponent()
        
        webView.loadFileURL(htmlUrl, allowingReadAccessTo: htmlDirectory)
    }
    
    private func setupNotificationObservers() {
        // Listen for kill detection events from the extension
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKillDetected),
            name: NSNotification.Name("KillDetected"),
            object: nil
        )
    }
    
    // MARK: - Video Recording System
    
    private func setupVideoRecording() {
        let appGroupID = "group.com.clashmonitor.shared2"
        appGroupDefaults = UserDefaults(suiteName: appGroupID)
        
        if let defaults = appGroupDefaults {
            print("✅ App Groups monitoring initialized for: \(appGroupID)")
            
            // Test App Groups write/read functionality
            let testKey = "testConnection"
            let testValue = Date().timeIntervalSince1970
            defaults.set(testValue, forKey: testKey)
            defaults.synchronize()
            
            let readValue = defaults.double(forKey: testKey)
            if readValue == testValue {
                print("✅ App Groups read/write test PASSED: \(testValue)")
            } else {
                print("❌ App Groups read/write test FAILED: wrote \(testValue), read \(readValue)")
            }
            
            // Verify App Groups container exists
            if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
                print("📁 App Groups container: \(containerURL)")
            } else {
                print("⚠️ App Groups container not found - may affect communication")
            }
        } else {
            print("❌ Failed to initialize App Groups monitoring for: \(appGroupID)")
        }
        
        // Start monitoring timer for auto-start, kill detection, and session processing
        killDetectionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForAutoStartRecording()
            self?.checkForKillNotification()
            self?.checkForSessionProcessing()
        }
        
        NSLog("⏱️ Kill detection and session processing timer started (2.0s interval)")
    }
    
    private func checkForAutoStartRecording() {
        guard !hasAutoStarted,
              let defaults = appGroupDefaults else { return }
        
        let shouldStart = defaults.bool(forKey: "shouldStartRecording")
        
        if shouldStart {
            print("🎬 AUTO-START RECORDING REQUEST RECEIVED from extension!")
            
            // Clear the flag
            defaults.set(false, forKey: "shouldStartRecording")
            defaults.synchronize()
            
            // Extension handles video recording, just acknowledge
            hasAutoStarted = true
            
            print("✅ Extension-based recording acknowledged - extension handles video encoding")
        }
    }
    
    private func checkForKillNotification() {
        guard let defaults = appGroupDefaults else { 
            print("❌ App Groups defaults not available")
            return 
        }
        
        let killTime = defaults.object(forKey: "killDetectedAt") as? Double
        let shouldSave = defaults.bool(forKey: "shouldSaveHighlight")
        
        if let _ = killTime, shouldSave {
            print("🎯 KILL NOTIFICATION RECEIVED! Updating UI...")
            
            // Clear the flag
            defaults.set(false, forKey: "shouldSaveHighlight")
            defaults.synchronize()
            
            // Extension recorded timestamp, update UI only
            DispatchQueue.main.async {
                self.handleKillDetected()
            }
            
            print("✅ Kill notification processed - timestamp recorded in extension")
        }
    }
    
    private func checkForSessionProcessing() {
        NSLog("🔄 Checking for session processing...")
        let appGroupID = "group.com.clashmonitor.shared2"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            NSLog("❌ Could not get App Groups container for session processing")
            return
        }
        NSLog("📁 App Groups container: \(containerURL.path)")
        
        let rawSessionsDir = containerURL.appendingPathComponent("RawSessions")
        
        // Debug: Check if directory exists
        NSLog("📁 Checking RawSessions directory: \(rawSessionsDir.path)")
        
        // Debug: Check entire App Groups container for any .mov files
        do {
            let allContainerFiles = try FileManager.default.contentsOfDirectory(at: containerURL, includingPropertiesForKeys: nil)
            NSLog("📂 App Groups container has \(allContainerFiles.count) items")
            for item in allContainerFiles {
                if item.hasDirectoryPath {
                    NSLog("  📁 Directory: \(item.lastPathComponent)")
                    // Check inside subdirectories
                    if let subItems = try? FileManager.default.contentsOfDirectory(at: item, includingPropertiesForKeys: nil) {
                        let movFiles = subItems.filter { $0.pathExtension == "mov" }
                        if movFiles.count > 0 {
                            NSLog("    📹 Contains \(movFiles.count) .mov files: \(movFiles.map { $0.lastPathComponent })")
                        }
                    }
                } else if item.pathExtension == "mov" {
                    NSLog("  📹 .mov file: \(item.lastPathComponent)")
                }
            }
        } catch {
            NSLog("❌ Error checking App Groups root: \(error)")
        }
        
        if !FileManager.default.fileExists(atPath: rawSessionsDir.path) {
            // Create directory if it doesn't exist
            do {
                try FileManager.default.createDirectory(at: rawSessionsDir, withIntermediateDirectories: true)
                NSLog("📁 Created RawSessions directory: \(rawSessionsDir.path)")
            } catch {
                NSLog("❌ Failed to create RawSessions directory: \(error)")
            }
            return
        }
        
        do {
            let allFiles = try FileManager.default.contentsOfDirectory(at: rawSessionsDir, includingPropertiesForKeys: [.creationDateKey])
            let sessionFiles = allFiles.filter { $0.pathExtension == "mov" && $0.lastPathComponent.starts(with: "session_") }
            
            // Debug logging - always log what we find
            NSLog("📁 RawSessions directory contains \(allFiles.count) files, \(sessionFiles.count) are session files")
            if allFiles.count > 0 {
                for file in allFiles {
                    do {
                        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                        let size = attributes[.size] as? NSNumber ?? 0
                        let date = attributes[.creationDate] as? Date ?? Date.distantPast
                        NSLog("  - \(file.lastPathComponent) (\(ByteCountFormatter().string(fromByteCount: size.int64Value)), created: \(date))")
                    } catch {
                        NSLog("  - \(file.lastPathComponent) (error reading attributes: \(error))")
                    }
                }
            } else {
                NSLog("  📝 No files found in RawSessions directory")
            }
            
            let sortedSessionFiles = sessionFiles.sorted { file1, file2 in
                let date1 = (try? file1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                let date2 = (try? file2.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date.distantPast
                return date1 < date2
            }
            
            // Process the oldest unprocessed session
            if let oldestSession = sortedSessionFiles.first {
                NSLog("📹 Found raw session to process: \(oldestSession.lastPathComponent)")
                processRawSession(sessionURL: oldestSession)
            }
        } catch {
            NSLog("❌ Error reading RawSessions directory: \(error)")
        }
    }
    
    private func processRawSession(sessionURL: URL) {
        NSLog("🎬 Processing raw session: \(sessionURL.lastPathComponent)")
        
        // Load kill timestamps
        let appGroupID = "group.com.clashmonitor.shared2"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }
        
        let timestampsURL = containerURL.appendingPathComponent("KillTimestamps/timestamps.json")
        var killTimestamps: [Double] = []
        
        if FileManager.default.fileExists(atPath: timestampsURL.path) {
            do {
                let timestampData = try Data(contentsOf: timestampsURL)
                killTimestamps = try JSONSerialization.jsonObject(with: timestampData) as? [Double] ?? []
                print("📊 Loaded \(killTimestamps.count) kill timestamps")
            } catch {
                print("❌ Failed to load kill timestamps: \(error)")
            }
        }
        
        guard killTimestamps.count > 0 else {
            print("⚠️ No kill timestamps found - cleaning up session without processing")
            try? FileManager.default.removeItem(at: sessionURL)
            return
        }
        
        // Process clips in background
        DispatchQueue.global(qos: .utility).async {
            self.extractKillHighlights(from: sessionURL, killTimestamps: killTimestamps)
        }
    }
    
    private func extractKillHighlights(from sessionURL: URL, killTimestamps: [Double]) {
        print("🎯 Extracting \(killTimestamps.count) kill highlights from session video")
        
        let appGroupID = "group.com.clashmonitor.shared2"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }
        
        let documentsDir = containerURL.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
        
        let asset = AVAsset(url: sessionURL)
        let sessionDuration = asset.duration.seconds
        
        print("📊 Session duration: \(String(format: "%.1f", sessionDuration))s")
        
        // Debug: Check file size and asset properties
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: sessionURL.path)
            if let size = attributes[.size] as? NSNumber {
                print("📊 Session file size: \(ByteCountFormatter().string(fromByteCount: size.int64Value))")
            }
        } catch {
            print("❌ Error checking session file size: \(error)")
        }
        
        // Debug: Check asset tracks
        let videoTracks = asset.tracks(withMediaType: .video)
        print("📊 Video tracks: \(videoTracks.count)")
        
        if let videoTrack = videoTracks.first {
            let trackDuration = videoTrack.timeRange.duration.seconds
            let naturalSize = videoTrack.naturalSize
            print("📊 Video track duration: \(String(format: "%.1f", trackDuration))s")
            print("📊 Video track size: \(Int(naturalSize.width))x\(Int(naturalSize.height))")
        }
        
        // Validate session has content
        guard sessionDuration > 0 else {
            print("❌ Session duration is 0 - cannot extract clips")
            try? FileManager.default.removeItem(at: sessionURL)
            return
        }
        
        let dispatchGroup = DispatchGroup()
        var successCount = 0
        
        for (index, killTime) in killTimestamps.enumerated() {
            // Validate kill time is within session bounds
            guard killTime >= 0 && killTime <= sessionDuration else {
                print("❌ Invalid kill time \(String(format: "%.1f", killTime))s - session is only \(String(format: "%.1f", sessionDuration))s")
                continue
            }
            
            // Extract 10-second clip: 5s before kill + 5s after kill
            let startTime = max(0, killTime - 5.0)
            let endTime = min(sessionDuration, killTime + 5.0)
            
            // Ensure we have at least some content to extract
            guard endTime > startTime && (endTime - startTime) >= 1.0 else {
                print("❌ Invalid time range: \(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s")
                continue
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date(timeIntervalSinceNow: TimeInterval(index)))
            
            let clipURL = documentsDir.appendingPathComponent("COD_Kill_\(timestamp).mp4")
            
            print("📹 Extracting clip \(index + 1): \(String(format: "%.1f", startTime))s - \(String(format: "%.1f", endTime))s (\(String(format: "%.1f", endTime - startTime))s duration)")
            
            dispatchGroup.enter()
            extractClip(from: asset, startTime: startTime, endTime: endTime, outputURL: clipURL) { success in
                if success {
                    print("✅ Kill highlight \(index + 1) extracted: \(clipURL.lastPathComponent)")
                    successCount += 1
                } else {
                    print("❌ Failed to extract kill highlight \(index + 1)")
                }
                dispatchGroup.leave()
            }
        }
        
        // Clean up after all clips are processed
        dispatchGroup.notify(queue: .global(qos: .utility)) {
            print("🎯 Clip extraction completed: \(successCount)/\(killTimestamps.count) successful")
            
            // Clean up raw session and timestamps
            try? FileManager.default.removeItem(at: sessionURL)
            
            let timestampsURL = containerURL.appendingPathComponent("KillTimestamps/timestamps.json")
            try? FileManager.default.removeItem(at: timestampsURL)
            
            print("🗑️ Raw session and timestamps cleaned up")
            
            // Update UI with new videos
            DispatchQueue.main.async {
                self.updateVideoList()
            }
        }
    }
    
    private func extractClip(from asset: AVAsset, startTime: Double, endTime: Double, outputURL: URL, completion: @escaping (Bool) -> Void) {
        let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputURL = outputURL
        exportSession?.outputFileType = .mp4
        
        let startCMTime = CMTime(seconds: startTime, preferredTimescale: 1000)
        let endCMTime = CMTime(seconds: endTime, preferredTimescale: 1000)
        exportSession?.timeRange = CMTimeRange(start: startCMTime, end: endCMTime)
        
        exportSession?.exportAsynchronously {
            let success = exportSession?.status == .completed
            if !success {
                print("❌ Export failed: \(exportSession?.error?.localizedDescription ?? "Unknown error")")
                print("❌ Export status: \(exportSession?.status.rawValue ?? -1)")
            }
            completion(success)
        }
    }
    
    // Extension handles all video recording and encoding
    
    
    @objc private func handleKillDetected() {
        // Update the web UI
        webView.evaluateJavaScript("window.addKillEvent()", completionHandler: nil)
        
        // Refresh video list after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.updateVideoList()
        }
    }
    
    private func updateVideoList() {
        // Get list of videos from App Groups Documents folder (where extension saves files)
        let appGroupID = "group.com.clashmonitor.shared2"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            print("❌ Could not get App Groups container URL")
            return
        }
        let documentsURL = containerURL.appendingPathComponent("Documents")
        
        print("📂 Updating video list from: \(documentsURL.path)")
        
        // Create Documents directory if it doesn't exist
        try? FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
            print("📁 Found \(files.count) total files in Documents")
            
            let videoFiles = files.filter { 
                $0.pathExtension == "mp4" && $0.lastPathComponent.starts(with: "COD_Kill_")
            }
            print("🎬 Found \(videoFiles.count) COD_Kill video files")
            
            for file in videoFiles {
                print("  - \(file.lastPathComponent)")
            }
            
            let videos = videoFiles.map { url -> [String: String] in
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = attributes?[.size] as? NSNumber ?? 0
                let date = attributes?[.creationDate] as? Date ?? Date()
                
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let sizeString = formatter.string(fromByteCount: Int64(size.intValue))
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateStyle = .short
                dateFormatter.timeStyle = .short
                let dateString = dateFormatter.string(from: date)
                
                return [
                    "name": url.lastPathComponent,
                    "path": url.path,
                    "size": sizeString,
                    "date": dateString
                ]
            }
            
            // Also read session logs for proper grouping
            let sessionLogs = loadSessionLogs(from: containerURL)
            
            let dataToSend = [
                "videos": videos,
                "sessions": sessionLogs
            ]
            
            let jsonData = try JSONSerialization.data(withJSONObject: dataToSend, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{\"videos\":[], \"sessions\":[]}"
            
            print("🌐 Updating web UI with \(videos.count) videos and \(sessionLogs.count) session events")
            webView.evaluateJavaScript("window.updateVideoListWithSessions(\(jsonString))", completionHandler: { result, error in
                if let error = error {
                    print("❌ JavaScript error updating video list: \(error)")
                } else {
                    print("✅ Successfully updated web UI video list with sessions")
                }
            })
        } catch {
            print("❌ Error loading videos: \(error)")
        }
    }
    
    private func loadSessionLogs(from containerURL: URL) -> [[String: Any]] {
        let sessionLogsURL = containerURL.appendingPathComponent("SessionLogs/sessions.json")
        
        guard FileManager.default.fileExists(atPath: sessionLogsURL.path) else {
            print("📝 No session logs found")
            return []
        }
        
        do {
            let data = try Data(contentsOf: sessionLogsURL)
            if let sessions = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                print("📝 Loaded \(sessions.count) session events")
                return sessions
            }
        } catch {
            print("❌ Error loading session logs: \(error)")
        }
        
        return []
    }
    
    private func startMonitoring() {
        // Show broadcast picker
        let picker = RPSystemBroadcastPickerView()
        picker.preferredExtension = "com.clashmonitor.app2.BroadcastExtension2"
        picker.showsMicrophoneButton = false
        
        // Simulate button tap to show picker
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.sendActions(for: .touchUpInside)
                break
            }
        }
        
        // VideoRecordingManager will auto-start when extension broadcasts
        
        // Update UI
        webView.evaluateJavaScript("window.setMonitoringStatus(true)", completionHandler: nil)
        appState.isMonitoring = true
    }
    
    private func stopMonitoring() {
        // Extension handles video recording, just update UI
        
        // Update shared defaults to stop extension
        let appGroupID = "group.com.clashmonitor.shared2"
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            print("❌ Failed to access App Group for stopping broadcast")
            return
        }
        
        defaults.set(false, forKey: "broadcastStatus")
        defaults.synchronize()
        print("✅ Broadcast status set to false")
        
        // Update UI
        webView.evaluateJavaScript("window.setMonitoringStatus(false)", completionHandler: nil)
        appState.isMonitoring = false
    }
    
    private func launchGame() {
        let codMobileURL = URL(string: "codmobile://")!
        let appStoreURL = URL(string: "https://apps.apple.com/app/call-of-duty-mobile/id1287282214")!
        
        if UIApplication.shared.canOpenURL(codMobileURL) {
            UIApplication.shared.open(codMobileURL)
        } else {
            UIApplication.shared.open(appStoreURL)
        }
    }
    
    private func playVideo(at path: String) {
        let url = URL(fileURLWithPath: path)
        let player = AVPlayer(url: url)
        let playerViewController = AVPlayerViewController()
        playerViewController.player = player
        
        present(playerViewController, animated: true) {
            player.play()
        }
    }
}

// MARK: - WKNavigationDelegate
extension WebViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Process any pending sessions first
        checkForSessionProcessing()
        
        // Update initial state
        updateVideoList()
        
        let isMonitoring = appState.isMonitoring
        webView.evaluateJavaScript("window.setMonitoringStatus(\(isMonitoring))", completionHandler: nil)
    }
}

// MARK: - WKScriptMessageHandler
extension WebViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String: Any],
              let action = dict["action"] as? String else {
            return
        }
        
        switch action {
        case "startMonitoring":
            startMonitoring()
            
        case "stopMonitoring":
            stopMonitoring()
            
        case "launchGame":
            launchGame()
            
        case "playVideo":
            if let data = dict["data"] as? [String: Any],
               let path = data["path"] as? String {
                playVideo(at: path)
            }
            
        case "requestState":
            // Process any pending sessions before updating video list
            checkForSessionProcessing()
            updateVideoList()
            
        default:
            print("Unknown action: \(action)")
        }
    }
}

// MARK: - SwiftUI Wrapper
struct WebViewWrapper: UIViewControllerRepresentable {
    typealias UIViewControllerType = WebViewController
    
    let appState: AppState
    let notificationManager: NotificationManager
    
    func makeUIViewController(context: Context) -> WebViewController {
        return WebViewController(appState: appState, notificationManager: notificationManager)
    }
    
    func updateUIViewController(_ uiViewController: WebViewController, context: Context) {
        // Update if needed
    }
}

