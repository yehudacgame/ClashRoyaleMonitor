import ReplayKit
import CoreMedia
import CoreImage
import AudioToolbox
import AVFoundation

@objc(SampleHandler)
public class SampleHandler: RPBroadcastSampleHandler {
    private var frameCount = 0
    private var visionProcessor: VisionProcessor?
    private var killDetected = false
    
    // 10-second cyclic buffer with immediate save on kill
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var bufferStartTime: CMTime?
    private var frameWidth: Int = 0
    private var frameHeight: Int = 0
    private var currentBufferURL: URL?
    private var buffersCreated = 0
    
    // Kill detection cooldown
    private var lastKillTime: Date = Date.distantPast
    
    override init() {
        super.init()
        visionProcessor = VisionProcessor()
    }
    
    public override func broadcastStarted(withSetupInfo setupInfo: [String : NSObject]?) {
        super.broadcastStarted(withSetupInfo: setupInfo)
        NSLog("🚀 Broadcast started - 10-second cyclic buffer with immediate save on kill")
        
        // Log session start for UI grouping
        logSessionEvent(type: "start")
        
        // Reset kill detection state
        lastKillTime = Date.distantPast
        buffersCreated = 0
        
        // Notify main app
        notifyMainAppToStartRecording()
    }
    
    public override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        if sampleBufferType == .video {
            frameCount += 1
            
            // Encode every frame to cyclic buffer
            encodeFrameToCyclicBuffer(sampleBuffer)
            
            // Log every 500 frames to verify processing
            if frameCount % 500 == 0 {
                NSLog("📹 Processed \(frameCount) frames, buffer \(buffersCreated)")
            }
            
            // OCR detection every 10 frames - saves buffer immediately on kill
            if frameCount % 10 == 0 {
                processFrameForKillDetection(sampleBuffer)
            }
        }
        
        // CRITICAL: Always call super to maintain broadcast stream
        super.processSampleBuffer(sampleBuffer, with: sampleBufferType)
    }
    
    private func processFrameForKillDetection(_ sampleBuffer: CMSampleBuffer) {
        // Skip OCR if we're in cooldown period
        guard !killDetected else { 
            return 
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { 
            return 
        }
        
        // Store current video timestamp for accurate kill timing
        let currentVideoTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        
        // EXPANDED CROP for COD Mobile kill notifications
        // COD Mobile kill notifications can appear in multiple locations
        let cropRect: CGRect
        if frameWidth > 0 && frameHeight > 0 {
            // Larger crop area - top 30% of screen, center 80% horizontally
            let cropX = CGFloat(frameWidth) * 0.1
            let cropY = CGFloat(frameHeight) * 0.1
            let cropWidth = CGFloat(frameWidth) * 0.8
            let cropHeight = CGFloat(frameHeight) * 0.3
            cropRect = CGRect(x: cropX, y: cropY, width: cropWidth, height: cropHeight)
            
            // Debug crop area
            if self.frameCount % 200 == 0 {
                NSLog("🔍 Crop area: x=\(Int(cropX)), y=\(Int(cropY)), w=\(Int(cropWidth)), h=\(Int(cropHeight))")
            }
        } else {
            // Larger default for portrait iPhone (1170x2532)
            cropRect = CGRect(x: 117, y: 253, width: 936, height: 760)
        }
        
        let croppedImage = ciImage.cropped(to: cropRect)
        
        // Debug OCR processing frequency  
        if self.frameCount % 50 == 0 {
            NSLog("🔍 Processing frame \(self.frameCount) for OCR kill detection...")
        }
        
        // Process only the cropped region for kill detection
        visionProcessor?.processImage(croppedImage) { [weak self] recognizedText in
            guard let self = self else { return }
            
            // Enhanced OCR logging to debug detection issues
            if !recognizedText.isEmpty {
                if self.frameCount % 50 == 0 { // More frequent logging
                    print("📝 OCR found \(recognizedText.count) text items on frame \(self.frameCount)")
                    for (index, text) in recognizedText.prefix(3).enumerated() {
                        print("  [\(index)] '\(text)'")
                    }
                }
            }
            
            guard !recognizedText.isEmpty, !self.killDetected else { return }
            
            // Check for specific kill notification patterns (more precise)
            for text in recognizedText {
                let upperText = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Log all detected text more frequently to debug kill detection
                if !upperText.isEmpty && self.frameCount % 100 == 0 {
                    NSLog("📝 OCR text: '\(upperText)'")
                }
                
                // Precise detection using Levenshtein distance for "ELIMINATED"
                let targetWord = "ELIMINATED"
                let isKillNotification = self.isEliminatedText(upperText, target: targetWord)
                
                if isKillNotification {
                    NSLog("🎯 LEGITIMATE KILL DETECTED in text: '\(text)'")
                    NSLog("🎯 Original text: '\(upperText)'")
                    self.onKillDetected(at: currentVideoTime)
                    break
                } else {
                    // Log potential text that didn't match ELIMINATED patterns
                    if upperText.count >= 5 && upperText.count <= 15 { // Only log reasonable length text
                        NSLog("🔍 Potential text (not ELIMINATED): '\(upperText)'")
                    }
                }
            }
        }
    }
    
    // MARK: - Levenshtein Distance Detection
    
    private func isEliminatedText(_ text: String, target: String) -> Bool {
        // Check if text contains "ELIMINATED" with fuzzy matching
        let words = text.split(separator: " ").map(String.init)
        
        for word in words {
            let distance = levenshteinDistance(word, target)
            let similarity = 1.0 - (Double(distance) / Double(max(word.count, target.count)))
            
            // Accept if similarity is >= 80% (allows 1-2 OCR errors in "ELIMINATED")
            if similarity >= 0.8 {
                NSLog("🎯 Found ELIMINATED match: '\(word)' -> '\(target)' (similarity: \(Int(similarity * 100))%)")
                return true
            }
        }
        
        return false
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let s1Count = s1Array.count
        let s2Count = s2Array.count
        
        if s1Count == 0 { return s2Count }
        if s2Count == 0 { return s1Count }
        
        var matrix = Array(repeating: Array(repeating: 0, count: s2Count + 1), count: s1Count + 1)
        
        for i in 0...s1Count {
            matrix[i][0] = i
        }
        
        for j in 0...s2Count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Count {
            for j in 1...s2Count {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,        // deletion
                    matrix[i][j - 1] + 1,        // insertion
                    matrix[i - 1][j - 1] + cost  // substitution
                )
            }
        }
        
        return matrix[s1Count][s2Count]
    }
    
    private func logSessionEvent(type: String) {
        let appGroupID = "group.com.clashmonitor.shared2"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }
        
        let sessionLogsDir = containerURL.appendingPathComponent("SessionLogs")
        try? FileManager.default.createDirectory(at: sessionLogsDir, withIntermediateDirectories: true)
        
        let sessionLogURL = sessionLogsDir.appendingPathComponent("sessions.json")
        
        let sessionEvent: [String: Any] = [
            "type": type,
            "timestamp": Date().timeIntervalSince1970,
            "date": ISO8601DateFormatter().string(from: Date())
        ]
        
        // Read existing sessions
        var sessions: [[String: Any]] = []
        if let data = try? Data(contentsOf: sessionLogURL),
           let existingSessions = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            sessions = existingSessions
        }
        
        // Add new session event
        sessions.append(sessionEvent)
        
        // Write back to file
        if let jsonData = try? JSONSerialization.data(withJSONObject: sessions, options: .prettyPrinted) {
            try? jsonData.write(to: sessionLogURL)
            NSLog("📝 Session \(type) logged: \(sessionEvent["date"] ?? "")")
        }
    }
    
    private func onKillDetected(at videoTime: CMTime) {
        // Prevent spam detections (minimum 3 seconds between kills)
        let now = Date()
        guard now.timeIntervalSince(lastKillTime) >= 3.0 else {
            NSLog("🎯 Kill detected but too soon after last kill (cooldown)")
            return
        }
        
        // Set cooldown flag immediately to prevent duplicate detections
        killDetected = true
        lastKillTime = now
        
        // Save current buffer immediately and start new one
        saveCurrentBufferAsKillClip()
        restartCyclicBuffer()
        
        NSLog("🎯 Kill detected - buffer saved as clip, restarting cyclic buffer")
        
        // Trigger immediate feedback
        playKillSound()
        
        // Notify main app for UI update
        notifyMainAppOfKillDetection()
        
        // Reset cooldown after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.killDetected = false
        }
    }
    
    private func getBufferRelativeTime(videoTime: CMTime) -> Double {
        guard let startTime = bufferStartTime else {
            NSLog("⚠️ No buffer start time available")
            return 0.0
        }
        
        let elapsed = CMTimeGetSeconds(CMTimeSubtract(videoTime, startTime))
        return max(0, elapsed) // Ensure positive timestamp
    }
    
    
    private func playKillSound() {
        DispatchQueue.main.async {
            AudioServicesPlaySystemSound(1106) // Tock sound
        }
    }
    
    private func notifyMainAppOfKillDetection() {
        let timestamp = Date().timeIntervalSince1970
        let appGroupID = "group.com.clashmonitor.shared2"
        
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return
        }
        
        // Set the kill detection flags for main app UI updates only
        defaults.set(timestamp, forKey: "killDetectedAt")
        defaults.set(true, forKey: "shouldSaveHighlight")
        defaults.synchronize()
        
        NSLog("✅ Kill detection notified to main app for UI update")
    }
    
    private func notifyMainAppToStartRecording() {
        let appGroupID = "group.com.clashmonitor.shared2"
        
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return
        }
        
        NSLog("🎬 Notifying main app to start video recording...")
        
        // Set flag to trigger automatic recording start in main app
        defaults.set(true, forKey: "shouldStartRecording")
        defaults.set(Date().timeIntervalSince1970, forKey: "recordingStartRequest")
        defaults.synchronize()
        
        NSLog("✅ Recording notification sent to main app")
    }
    
    // MARK: - 10-Second Cyclic Buffer
    
    private func encodeFrameToCyclicBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Get frame dimensions on first frame
        if frameWidth == 0 || frameHeight == 0 {
            if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                frameWidth = CVPixelBufferGetWidth(pixelBuffer)
                frameHeight = CVPixelBufferGetHeight(pixelBuffer)
                NSLog("📱 Frame dimensions: \(frameWidth)x\(frameHeight)")
            }
        }
        
        // Initialize buffer if needed
        if videoWriter == nil || videoWriter?.status != .writing {
            setupCyclicBuffer()
        }
        
        guard let writer = videoWriter,
              let input = videoInput,
              writer.status == .writing else {
            return
        }
        
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // Initialize buffer timing on first frame
        if bufferStartTime == nil {
            bufferStartTime = currentTime
            writer.startSession(atSourceTime: currentTime)
            NSLog("✅ Cyclic buffer started at time: \(CMTimeGetSeconds(currentTime))s")
        }
        
        // Check if buffer has been recording for 10+ seconds - restart it
        let bufferDuration = getBufferRelativeTime(videoTime: currentTime)
        if bufferDuration >= 10.0 {
            restartCyclicBuffer()
            return
        }
        
        // Append frame to buffer
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }
    
    private func setupCyclicBuffer() {
        guard frameWidth > 0 && frameHeight > 0 else { return }
        
        let appGroupID = "group.com.clashmonitor.shared2"
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            return
        }
        
        let documentsDir = containerURL.appendingPathComponent("Documents")
        try? FileManager.default.createDirectory(at: documentsDir, withIntermediateDirectories: true)
        
        // Create temporary buffer file
        let bufferURL = documentsDir.appendingPathComponent("temp_buffer_\(buffersCreated).mov")
        currentBufferURL = bufferURL
        
        do {
            videoWriter = try AVAssetWriter(outputURL: bufferURL, fileType: .mov)
            
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: frameWidth,
                AVVideoHeightKey: frameHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000, // Higher quality for kill clips
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel,
                    AVVideoAllowFrameReorderingKey: false,
                    AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCAVLC
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            // Apply portrait->landscape rotation if needed
            if frameHeight > frameWidth {
                videoInput?.transform = CGAffineTransform(rotationAngle: -CGFloat.pi / 2)
            }
            
            if let input = videoInput, videoWriter?.canAdd(input) == true {
                videoWriter?.add(input)
            }
            
            let success = videoWriter?.startWriting() ?? false
            if success {
                NSLog("✅ Cyclic buffer \(buffersCreated) initialized: \(bufferURL.lastPathComponent)")
            } else {
                NSLog("❌ Failed to start cyclic buffer \(buffersCreated)")
                videoWriter = nil
                videoInput = nil
                currentBufferURL = nil
            }
            
        } catch {
            NSLog("❌ Failed to setup cyclic buffer: \(error)")
            videoWriter = nil
            videoInput = nil
            currentBufferURL = nil
        }
    }
    
    private func saveCurrentBufferAsKillClip() {
        guard let writer = videoWriter,
              let input = videoInput,
              let bufferURL = currentBufferURL else {
            NSLog("⚠️ No active buffer to save as kill clip")
            return
        }
        
        // Create final filename for kill clip
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let finalURL = bufferURL.deletingLastPathComponent().appendingPathComponent("COD_Kill_\(timestamp).mp4")
        
        // Finish current buffer synchronously
        input.markAsFinished()
        
        let semaphore = DispatchSemaphore(value: 0)
        var saveSuccess = false
        
        writer.finishWriting {
            if writer.status == .completed {
                // Move temp buffer to final kill clip location
                do {
                    if FileManager.default.fileExists(atPath: finalURL.path) {
                        try FileManager.default.removeItem(at: finalURL)
                    }
                    try FileManager.default.moveItem(at: bufferURL, to: finalURL)
                    NSLog("✅ Kill clip saved: \(finalURL.lastPathComponent)")
                    saveSuccess = true
                } catch {
                    NSLog("❌ Failed to save kill clip: \(error)")
                    try? FileManager.default.removeItem(at: bufferURL)
                }
            } else {
                NSLog("❌ Buffer completion failed, removing temp file")
                try? FileManager.default.removeItem(at: bufferURL)
            }
            semaphore.signal()
        }
        
        // Wait for completion (max 2 seconds)
        _ = semaphore.wait(timeout: .now() + 2.0)
        
        // Clear current buffer references
        videoWriter = nil
        videoInput = nil
        currentBufferURL = nil
        bufferStartTime = nil
        
        if saveSuccess {
            NSLog("✅ Kill clip processing completed successfully")
        }
    }
    
    private func restartCyclicBuffer() {
        // Clean up current buffer if it exists
        if let writer = videoWriter, let input = videoInput, let bufferURL = currentBufferURL {
            input.markAsFinished()
            writer.finishWriting { 
                // Remove temp buffer since we're just restarting (not saving)
                try? FileManager.default.removeItem(at: bufferURL)
            }
        }
        
        // Clear state
        videoWriter = nil
        videoInput = nil
        currentBufferURL = nil
        bufferStartTime = nil
        buffersCreated += 1
        
        NSLog("🔄 Cyclic buffer restarted (buffer \(buffersCreated))")
    }
    
    private func finishCyclicBuffer() {
        // Clean up any active buffer
        if let writer = videoWriter, let input = videoInput, let bufferURL = currentBufferURL {
            NSLog("🔌 Cleaning up active cyclic buffer")
            input.markAsFinished()
            writer.finishWriting { 
                // Remove temp buffer
                try? FileManager.default.removeItem(at: bufferURL)
                NSLog("🔌 Cyclic buffer cleanup completed")
            }
        }
        
        // Clear state
        videoWriter = nil
        videoInput = nil
        currentBufferURL = nil
        bufferStartTime = nil
        
        NSLog("🏁 Cyclic buffer session ended - \(buffersCreated) buffers created")
    }
    
    public override func broadcastPaused() {
        super.broadcastPaused()
    }
    
    public override func broadcastResumed() {
        super.broadcastResumed()
    }
    
    public override func broadcastFinished() {
        NSLog("🔚 Broadcast finished - finalizing cyclic buffer")
        
        // Debug the buffer state before finishing
        NSLog("📊 Buffer state at broadcast finish - writer: \(videoWriter != nil), input: \(videoInput != nil), currentBufferURL: \(currentBufferURL != nil)")
        if let writer = videoWriter {
            NSLog("📊 Writer status: \(writer.status.rawValue)")
        }
        if let bufferURL = currentBufferURL {
            NSLog("📊 Current buffer: \(bufferURL.lastPathComponent)")
        }
        
        // Log session end for UI grouping
        logSessionEvent(type: "end")
        
        // Finish cyclic buffer system
        finishCyclicBuffer()
        
        super.broadcastFinished()
    }
    
    public override func finishBroadcastWithError(_ error: Error) {
        NSLog("❌ Broadcast error: \(error.localizedDescription)")
        super.finishBroadcastWithError(error)
    }
}