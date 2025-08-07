import ReplayKit
import CoreMedia
import CoreImage
import AudioToolbox

@objc(ClashRoyaleSampleHandler)
public final class ClashRoyaleSampleHandler: RPBroadcastSampleHandler {
    private var frameCount = 0
    private var visionProcessor: VisionProcessor?
    private var killDetected = false
    
    public override init() {
        super.init()
        visionProcessor = VisionProcessor()
    }
    
    public override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        super.broadcastStarted(withSetupInfo: setupInfo)
    }
    
    public override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        if sampleBufferType == .video {
            frameCount += 1
            
            // OCR detection every N frames to reduce memory pressure
            if frameCount % 10 == 0 {
                processFrameForKillDetection(sampleBuffer)
            }
        }
        
        super.processSampleBuffer(sampleBuffer, with: sampleBufferType)
    }
    
    private func processFrameForKillDetection(_ sampleBuffer: CMSampleBuffer) {
        // Skip OCR if we're in cooldown period
        guard !killDetected else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        visionProcessor?.processImage(ciImage) { [weak self] recognizedText in
            guard let self = self, !recognizedText.isEmpty, !self.killDetected else { return }
            
            // Check for kill indicators
            for text in recognizedText {
                let upperText = text.uppercased()
                
                if upperText.contains("KILL") || upperText.contains("ELIMINATED") || upperText.contains("ELIMINA") {
                    self.onKillDetected()
                    break
                }
            }
        }
    }
    
    private func onKillDetected() {
        // Set cooldown flag immediately to prevent duplicate detections
        killDetected = true
        
        // Trigger immediate feedback
        playKillSound()
        
        // Notify main app to save video
        notifyMainAppOfKill()
        
        // Reset cooldown after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.killDetected = false
        }
    }
    
    private func playKillSound() {
        DispatchQueue.main.async {
            AudioServicesPlaySystemSound(1106) // Tock sound
        }
    }
    
    public override func broadcastPaused() {
        super.broadcastPaused()
    }
    
    public override func broadcastResumed() {
        super.broadcastResumed()
    }
    
    public override func broadcastFinished() {
        super.broadcastFinished()
    }
    
    public override func finishBroadcastWithError(_ error: Error) {
        print("Broadcast error: \(error.localizedDescription)")
        super.finishBroadcastWithError(error)
    }
    
    private func notifyMainAppOfKill() {
        let timestamp = Date().timeIntervalSince1970
        
        // Use UserDefaults with App Groups for proper container access
        let appGroupID = "group.com.clashmonitor.shared2"
        
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            print("❌ Failed to create UserDefaults for app group: \(appGroupID)")
            return
        }
        
        // Set the kill detection flags
        defaults.set(timestamp, forKey: "killDetectedAt")
        defaults.set(true, forKey: "shouldSaveHighlight")
        
        // Ensure data is synchronized immediately
        defaults.synchronize()
        
        print("✅ Kill detected and notified to main app at timestamp: \(timestamp)")
    }
}