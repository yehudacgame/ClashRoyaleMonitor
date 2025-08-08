import Foundation
import AVFoundation
import UserNotifications
import CoreMedia
import CoreVideo

/// Main app video recording manager with hardware-accelerated rolling buffer
/// Receives frames from extension and maintains 10-second cyclic buffer
class VideoRecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var lastSaveStatus: String = ""
    @Published var savedVideosCount: Int = 0
    
    private var recordingStartTime: Date?
    // NO RPScreenRecorder - frames come from extension
    
    private let fileManager = FileManager.default
    private var appGroupDefaults: UserDefaults?
    
    // Hardware-accelerated rolling video buffer (10 seconds)
    private var videoWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var currentBufferURL: URL?
    
    // Rolling buffer management
    private var bufferStartTime: CMTime?
    private let bufferDuration: TimeInterval = 10.0
    private var isBufferReady = false
    
    // Background recording queue
    private let recordingQueue = DispatchQueue(label: "video.recording.queue", qos: .userInitiated)
    
    // Monitoring App Groups for kill notifications and frame data
    private var killDetectionTimer: Timer?
    private var frameProcessingTimer: Timer?
    
    // Frame dimensions
    private var frameWidth: Int = 1170  // Default iPhone portrait
    private var frameHeight: Int = 2532
    private var pixelFormatType: OSType = kCVPixelFormatType_32BGRA
    
    override init() {
        super.init()
        setupAppGroupMonitoring()
    }
    
    private func setupAppGroupMonitoring() {
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
        
        killDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForAutoStartRecording()
            self?.checkForKillNotification()
        }
        
        // Monitor for frames from extension (high frequency)
        frameProcessingTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            self?.checkForNewFrames()
        }
        
        print("⏱️ Kill detection timer started (0.5s interval)")
    }
    
    private var lastKillProcessTime: Date = Date.distantPast
    private var hasAutoStarted = false
    
    private func checkForAutoStartRecording() {
        guard !hasAutoStarted,
              let defaults = appGroupDefaults else { return }
        
        let shouldStart = defaults.bool(forKey: "shouldStartRecording")
        
        if shouldStart {
            print("🎬 AUTO-START RECORDING REQUEST RECEIVED from extension!")
            
            // Clear the flag
            defaults.set(false, forKey: "shouldStartRecording")
            defaults.synchronize()
            
            // Start recording automatically
            hasAutoStarted = true
            startRecording()
            
            print("✅ Video recording auto-started in response to extension broadcast")
        }
    }
    
    private func checkForKillNotification() {
        guard let defaults = appGroupDefaults else { 
            print("❌ App Groups defaults not available")
            return 
        }
        
        // Debug: Check what keys exist in App Groups
        let killTime = defaults.object(forKey: "killDetectedAt") as? Double
        let shouldSave = defaults.bool(forKey: "shouldSaveHighlight")
        
        // Show current state occasionally
        static var logCounter = 0
        logCounter += 1
        if logCounter % 60 == 0 { // Log every 30 seconds (0.5s * 60)
            print("📡 App Groups status: killDetectedAt=\(killTime ?? 0), shouldSaveHighlight=\(shouldSave)")
        }
        
        if let _ = killTime, shouldSave {
            let now = Date()
            guard now.timeIntervalSince(lastKillProcessTime) >= 3.0 else { 
                print("⏳ Kill processing cooldown active (3s)") 
                return 
            }
            
            print("🎯 KILL NOTIFICATION RECEIVED! Processing video save...")
            
            // Clear the flag using only UserDefaults
            defaults.set(false, forKey: "shouldSaveHighlight")
            defaults.synchronize()
            
            lastKillProcessTime = now
            saveLastTenSeconds()
            
            print("✅ Kill notification processed, video save initiated")
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        recordingStartTime = Date()
        lastSaveStatus = "Recording started"
        
        // Setup video writer for hardware encoding
        recordingQueue.async { [weak self] in
            self?.setupVideoWriter()
            DispatchQueue.main.async {
                self?.lastSaveStatus = "✅ Hardware encoder ready - waiting for frames from extension"
            }
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        recordingQueue.async { [weak self] in
            self?.finishCurrentWriter()
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.lastSaveStatus = "Recording stopped"
        }
    }
    
    private func saveLastTenSeconds() {
        print("💾 Kill detected - initiating video save...")
        lastSaveStatus = "Saving highlight..."
        
        recordingQueue.async { [weak self] in
            guard let self = self else { 
                print("❌ Self reference lost during save")
                return 
            }
            
            print("🎬 Starting buffer save on recording queue...")
            
            self.saveCurrentBuffer { [weak self] success, savedURL in
                DispatchQueue.main.async {
                    if success, let url = savedURL {
                        self?.savedVideosCount += 1
                        let message = "Highlight saved! (\(self?.savedVideosCount ?? 0) total)"
                        self?.lastSaveStatus = message
                        print("✅ \(message)")
                        print("📁 Saved to: \(url.lastPathComponent)")
                    } else {
                        let errorMessage = "Failed to save highlight"
                        self?.lastSaveStatus = errorMessage
                        print("❌ \(errorMessage)")
                    }
                }
            }
        }
    }
    
    // MARK: - Hardware-Accelerated Rolling Buffer Implementation
    
    private func checkForNewFrames() {
        guard isRecording else { return }
        
        // Check if extension has written frame data to App Groups
        guard let defaults = appGroupDefaults,
              let frameDataKey = defaults.data(forKey: "latestFrameData"),
              frameDataKey.count > 0 else {
            return
        }
        
        // Process frame on background queue
        recordingQueue.async { [weak self] in
            self?.processFrameData(frameDataKey)
        }
        
        // Clear the frame data after processing
        defaults.removeObject(forKey: "latestFrameData")
        defaults.synchronize()
    }
    
    private func processFrameData(_ frameData: Data) {
        // Create CVPixelBuffer from frame data
        guard let pixelBuffer = createPixelBuffer(from: frameData) else {
            return
        }
        
        // Create CMSampleBuffer from pixel buffer
        var sampleBuffer: CMSampleBuffer?
        var timingInfo = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(seconds: Date().timeIntervalSince1970, preferredTimescale: 600),
            decodeTimeStamp: CMTime.invalid
        )
        
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        
        if let format = formatDescription {
            CMSampleBufferCreateReadyWithImageBuffer(
                allocator: nil,
                imageBuffer: pixelBuffer,
                formatDescription: format,
                sampleTiming: &timingInfo,
                sampleBufferOut: &sampleBuffer
            )
            
            if let buffer = sampleBuffer {
                processSampleBuffer(buffer)
            }
        }
    }
    
    private func createPixelBuffer(from data: Data) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        
        let attrs = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            frameWidth,
            frameHeight,
            pixelFormatType,
            attrs,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        let baseAddress = CVPixelBufferGetBaseAddress(buffer)
        data.copyBytes(to: baseAddress!.assumingMemoryBound(to: UInt8.self), count: data.count)
        
        return buffer
    }
    
    private func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        // Initialize writer if needed
        if videoWriter == nil {
            setupVideoWriter()
        }
        
        guard let writer = videoWriter,
              let input = videoInput,
              writer.status == .writing else {
            return
        }
        
        // Record start time for buffer duration tracking
        if bufferStartTime == nil {
            bufferStartTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        }
        
        // Check if buffer duration exceeded (10 seconds)
        let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if let startTime = bufferStartTime {
            let elapsedTime = CMTimeGetSeconds(CMTimeSubtract(currentTime, startTime))
            
            if elapsedTime >= bufferDuration {
                // Start new rolling buffer
                restartRollingBuffer()
                return
            }
        }
        
        // Append video sample to writer
        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
            
            if !isBufferReady {
                isBufferReady = true
                DispatchQueue.main.async {
                    self.lastSaveStatus = "✅ Rolling buffer ready - monitoring for kills"
                }
            }
        }
    }
    
    private func setupVideoWriter() {
        // Create unique temporary URL for rolling buffer
        let tempDir = fileManager.temporaryDirectory
        let bufferURL = tempDir.appendingPathComponent("rolling_buffer_\(UUID().uuidString).mp4")
        currentBufferURL = bufferURL
        
        do {
            // Create hardware-accelerated video writer
            videoWriter = try AVAssetWriter(outputURL: bufferURL, fileType: .mp4)
            
            // Configure video input with hardware acceleration
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264, // Hardware accelerated
                AVVideoWidthKey: frameWidth,
                AVVideoHeightKey: frameHeight,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 8_000_000, // 8 Mbps for quality
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoH264EntropyModeKey: AVVideoH264EntropyModeCABAC,
                    AVVideoAllowFrameReorderingKey: false // Reduce latency
                ]
            ]
            
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true
            
            if let input = videoInput, videoWriter?.canAdd(input) == true {
                videoWriter?.add(input)
            }
            
            // Start writing session
            videoWriter?.startWriting()
            videoWriter?.startSession(atSourceTime: CMTime.zero)
            
            print("✅ Hardware-accelerated video writer initialized")
            
        } catch {
            print("❌ Failed to setup video writer: \(error)")
            currentBufferURL = nil
        }
    }
    
    private func restartRollingBuffer() {
        // Finish current writer
        finishCurrentWriter()
        
        // Reset buffer state
        bufferStartTime = nil
        isBufferReady = false
        
        // Start new writer
        setupVideoWriter()
        
        print("🔄 Rolling buffer restarted")
    }
    
    private func finishCurrentWriter() {
        guard let writer = videoWriter else { return }
        
        videoInput?.markAsFinished()
        
        writer.finishWriting {
            // Clean up old buffer file if exists
            if let url = self.currentBufferURL, self.fileManager.fileExists(atPath: url.path) {
                try? self.fileManager.removeItem(at: url)
            }
        }
        
        videoWriter = nil
        videoInput = nil
    }
    
    private func saveCurrentBuffer(completion: @escaping (Bool, URL?) -> Void) {
        guard let writer = videoWriter,
              let currentURL = currentBufferURL,
              isBufferReady else {
            print("❌ No buffer ready to save")
            completion(false, nil)
            return
        }
        
        // Create final save URL
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let timestamp = DateFormatter().apply {
            $0.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        }.string(from: Date())
        
        let finalURL = documentsDir.appendingPathComponent("COD_Kill_\(timestamp).mp4")
        
        print("💾 Saving kill highlight to: \(finalURL.lastPathComponent)")
        
        // Finish writing current buffer
        videoInput?.markAsFinished()
        
        writer.finishWriting { [weak self] in
            guard let self = self else {
                completion(false, nil)
                return
            }
            
            do {
                // Copy buffer to final location
                try self.fileManager.copyItem(at: currentURL, to: finalURL)
                
                // Restart rolling buffer
                self.restartRollingBuffer()
                
                completion(true, finalURL)
                
            } catch {
                print("❌ Failed to save buffer: \(error)")
                completion(false, nil)
            }
        }
    }
    
    deinit {
        killDetectionTimer?.invalidate()
        frameProcessingTimer?.invalidate()
        if isRecording {
            stopRecording()
        }
        finishCurrentWriter()
    }
}

extension DateFormatter {
    func apply(closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}