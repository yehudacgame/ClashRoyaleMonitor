import SwiftUI
import UIKit
import WebKit
import AVKit
import ReplayKit
import CoreData

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
    }
}

// MARK: - WebViewController
class WebViewController: UIViewController {
    private var webView: WKWebView!
    private var appState: AppState
    private var notificationManager: NotificationManager
    // private var videoRecordingManager: VideoRecordingManager?
    
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
        
        // Initialize video recording manager
        // videoRecordingManager = VideoRecordingManager()
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
        
        // Check for kill events from extension via App Groups
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForKillEvents()
        }
    }
    
    private func checkForKillEvents() {
        let appGroupID = "group.com.clashmonitor.shared2"
        guard let defaults = UserDefaults(suiteName: appGroupID) else { 
            print("❌ Failed to access App Group: \(appGroupID)")
            return 
        }
        
        if defaults.bool(forKey: "shouldSaveHighlight") {
            // Reset the flag
            defaults.set(false, forKey: "shouldSaveHighlight")
            defaults.synchronize()
            
            // Trigger kill event in UI
            handleKillDetected()
            
            print("✅ Kill event detected from extension and processed in web UI")
            
            // Save video if recording
            // videoRecordingManager?.saveCurrentBuffer()
        }
    }
    
    @objc private func handleKillDetected() {
        // Update the web UI
        webView.evaluateJavaScript("window.addKillEvent()", completionHandler: nil)
        
        // Refresh video list after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.updateVideoList()
        }
    }
    
    private func updateVideoList() {
        // Get list of videos from Documents folder
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey])
            let videoFiles = files.filter { 
                $0.pathExtension == "mp4" && $0.lastPathComponent.starts(with: "COD_Kill_")
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
            
            let jsonData = try JSONSerialization.data(withJSONObject: videos, options: [])
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
            
            webView.evaluateJavaScript("window.updateVideoList(\(jsonString))", completionHandler: nil)
        } catch {
            print("❌ Error loading videos: \(error)")
        }
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
        
        // Start video recording in main app
        // videoRecordingManager?.startRecording()
        
        // Update UI
        webView.evaluateJavaScript("window.setMonitoringStatus(true)", completionHandler: nil)
        appState.isMonitoring = true
    }
    
    private func stopMonitoring() {
        // Stop video recording
        // videoRecordingManager?.stopRecording()
        
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

