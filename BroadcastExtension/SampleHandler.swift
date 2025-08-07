import ReplayKit
import CoreMedia
import CoreImage
import AudioToolbox

@objc(SampleHandler)
public class SampleHandler: RPBroadcastSampleHandler {
    private var frameCount = 0
    private var visionProcessor: VisionProcessor?
    private var killDetected = false
    
    override init() {
        super.init()
        print("🚀 BroadcastExtension: Initializing...")
        visionProcessor = VisionProcessor()
        print("🚀 VisionProcessor initialized: \(visionProcessor != nil)")
    }
    
    public override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        super.broadcastStarted(withSetupInfo: setupInfo)
        print("🚀 BroadcastExtension: Started successfully")
    }
    
    public override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        if sampleBufferType == .video {
            frameCount += 1
            
            // Log every 100 frames to verify processing
            if frameCount % 100 == 0 {
                print("📹 Processed \(frameCount) video frames")
            }
            
            // OCR detection every 10 frames to reduce memory pressure
            if frameCount % 10 == 0 {
                print("🔍 Processing frame \(frameCount) for OCR")
                processFrameForKillDetection(sampleBuffer)
            }
        }
        
        // CRITICAL: Always call super to maintain broadcast stream
        super.processSampleBuffer(sampleBuffer, with: sampleBufferType)
    }
    
    private func processFrameForKillDetection(_ sampleBuffer: CMSampleBuffer) {
        // Skip OCR if we're in cooldown period
        guard !killDetected else { 
            print("⏳ Skipping OCR - in cooldown period")
            return 
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
            print("❌ Failed to get pixel buffer from sample")
            return 
        }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        print("🔍 Starting Vision processing for frame \(frameCount)")
        
        visionProcessor?.processImage(ciImage) { [weak self] recognizedText in
            guard let self = self else { return }
            
            print("📝 OCR completed. Found \(recognizedText.count) text items")
            if !recognizedText.isEmpty {
                print("📝 Recognized text: \(recognizedText)")
            }
            
            guard !recognizedText.isEmpty, !self.killDetected else { return }
            
            // Check for kill indicators
            for text in recognizedText {
                let upperText = text.uppercased()
                
                if upperText.contains("KILL") || upperText.contains("ELIMINATED") || upperText.contains("ELIMINA") {
                    print("🎯 KILL DETECTED in text: '\(text)'")
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
        
        // Notify main app to save video buffer
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
    
    private func notifyMainAppOfKill() {
        let timestamp = Date().timeIntervalSince1970
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
        print("❌ Broadcast error: \(error.localizedDescription)")
        super.finishBroadcastWithError(error)
    }
}