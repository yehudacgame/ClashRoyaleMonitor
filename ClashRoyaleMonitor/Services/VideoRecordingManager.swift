import Foundation
import ReplayKit
import AVFoundation
import UserNotifications

/// Main app video recording manager with hardware-accelerated rolling buffer
/// Maintains 10-second cyclic buffer and saves highlights when triggered by extension
class VideoRecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var lastSaveStatus: String = ""
    @Published var savedVideosCount: Int = 0
    
    private var recordingStartTime: Date?
    private var screenRecorder = RPScreenRecorder.shared()
    
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
    
    // Monitoring App Groups for kill notifications
    private var killDetectionTimer: Timer?
    
    override init() {
        super.init()
        setupAppGroupMonitoring()
    }
    
    private func setupAppGroupMonitoring() {
        appGroupDefaults = UserDefaults(suiteName: "group.com.clashmonitor.shared2")
        
        killDetectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForKillNotification()
        }
    }
    
    private var lastKillProcessTime: Date = Date.distantPast
    
    private func checkForKillNotification() {
        guard let defaults = appGroupDefaults else { return }
        
        let shouldSave = defaults.bool(forKey: "shouldSaveHighlight")
        
        if shouldSave {
            let now = Date()
            guard now.timeIntervalSince(lastKillProcessTime) >= 3.0 else { return }
            
            // Clear the flag using only UserDefaults
            defaults.set(false, forKey: "shouldSaveHighlight")
            defaults.synchronize()
            
            lastKillProcessTime = now
            saveLastTenSeconds()
            
            print("✅ Kill notification processed, video saved")
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        recordingStartTime = Date()
        lastSaveStatus = "Recording started"
        
        recordingQueue.async { [weak self] in
            self?.startContinuousRecording()
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        recordingQueue.async { [weak self] in
            self?.stopContinuousRecording()
        }
        
        DispatchQueue.main.async {
            self.isRecording = false
            self.lastSaveStatus = "Recording stopped"
        }
    }
    
    private func saveLastTenSeconds() {
        lastSaveStatus = "Saving highlight..."
        
        recordingQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.saveCurrentBuffer { [weak self] success, savedURL in
                DispatchQueue.main.async {
                    if success, let url = savedURL {
                        self?.savedVideosCount += 1
                        self?.lastSaveStatus = "Highlight saved! (\(self?.savedVideosCount ?? 0) total)"
                    } else {
                        self?.lastSaveStatus = "Failed to save highlight"
                    }
                }
            }
        }
    }
    
    // MARK: - Hardware-Accelerated Rolling Buffer Implementation
    
    private func startContinuousRecording() {
        guard screenRecorder.isAvailable else {
            DispatchQueue.main.async {
                self.lastSaveStatus = "❌ Screen recording not available"
            }
            return
        }
        
        // Configure for minimal latency and hardware acceleration
        screenRecorder.isMicrophoneEnabled = false // Disable mic for performance
        screenRecorder.isCameraEnabled = false
        
        print("🔄 Starting continuous screen recording for rolling buffer")
        
        screenRecorder.startCapture(handler: { [weak self] sampleBuffer, bufferType, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Screen capture error: \(error)")
                return
            }
            
            // Process video frames for rolling buffer
            if bufferType == .video {
                self.processSampleBuffer(sampleBuffer)
            }
            
        }) { [weak self] error in
            if let error = error {
                print("❌ Failed to start screen capture: \(error)")
                DispatchQueue.main.async {
                    self?.lastSaveStatus = "❌ Failed to start recording: \(error.localizedDescription)"
                    self?.isRecording = false
                }
            } else {
                print("✅ Screen capture started successfully")
                DispatchQueue.main.async {
                    self?.lastSaveStatus = "✅ Rolling buffer active - monitoring for kills"
                }
            }
        }
    }
    
    private func stopContinuousRecording() {
        print("🛑 Stopping continuous screen capture")
        screenRecorder.stopCapture { [weak self] error in
            if let error = error {
                print("❌ Error stopping capture: \(error)")
            } else {
                print("✅ Screen capture stopped")
            }
            
            // Clean up video writer
            self?.finishCurrentWriter()
        }
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
                AVVideoWidthKey: 1920,
                AVVideoHeightKey: 1080,
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