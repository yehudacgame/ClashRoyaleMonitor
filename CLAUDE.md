# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClashRoyaleMonitor is an iOS app that uses ReplayKit and Vision Framework for real-time game monitoring and video highlight capture. Originally designed for Clash Royale tower detection, it has evolved into a COD Mobile kill detection system that automatically saves 10-second highlight videos when kills are detected.

**Current Status (December 2024):** 
- ✅ **OCR Kill Detection**: Working with cropped region (94% memory reduction)
- ✅ **Hardware Video Encoding**: Extension handles 10-second rolling buffer
- ✅ **Web Interface**: COD Mobile Battle Royale theme with video playback
- ✅ **Memory Optimized**: Extension stays at ~25MB (under 50MB limit)
- ✅ **Single ReplayKit Instance**: Extension handles both video and OCR

**Requirements:** iOS 14.0+, physical device required for ReplayKit testing.

## Build Commands

### iOS Project (Xcode-based)
```bash
# Open project
open ClashRoyaleMonitor.xcodeproj

# Build and run (⌘R in Xcode - physical device required)
# Clean build: ⌘⇧K in Xcode

# Run tests
xcodebuild test -scheme ClashRoyaleMonitor -destination 'platform=iOS Simulator,name=iPhone 15'

# Clean via command line
xcodebuild clean -scheme ClashRoyaleMonitor
```

### Testing
Physical iOS device required for ReplayKit broadcast extension testing. Simulator cannot test screen recording functionality.

## Architecture

### Current Implementation: COD Mobile Kill Detection with Hardware Video Encoding

**CRITICAL ARCHITECTURE (December 2024):**

```
Extension (SampleHandler) - Single ReplayKit Instance:
┌─────────────────────────────────────────────┐
│ Frame → BOTH:                               │
│   1. Hardware Video Encoding (EVERY frame)  │
│   2. Cropped OCR Detection (every 10th)     │
│      ↓                                      │
│ Kill Detected → Save Video → Notify Main   │
│                                             │
│ Memory Usage: ~25MB (under 50MB limit)      │
└─────────────────────────────────────────────┘
           ↓
Main App: Updates UI, Shows Video List
```

**Extension Role (SampleHandler.swift):**
- ✅ Uses single ReplayKit instance for BOTH video encoding AND OCR
- ✅ Hardware encodes EVERY frame to rolling 10-second buffer (AVAssetWriter)
- ✅ OCR processes every 10th frame with **94% crop** (top 20% of screen)
- ✅ Detect "KILL", "ELIMINATED", "ELIMINA" with substring matching
- ✅ Saves video directly when kill detected, then notifies main app
- ✅ 2-second cooldown to prevent consecutive detections
- ✅ Memory stays at ~25MB (well under 50MB iOS limit)

**Main App Role (ClashRoyaleMonitorApp.swift):**
- ✅ **NO video capture** (would conflict with extension's ReplayKit)
- ✅ Monitor App Groups for kill notifications (0.5s polling)
- ✅ Update web UI when videos are saved
- ✅ Display saved videos from App Groups Documents folder
- ✅ Handle video playback through WKWebView bridge

### Key Components

**ReplayKit Architecture:**
- `BroadcastExtension/SampleHandler.swift`: OCR processing and kill detection
- `ClashRoyaleMonitor/Services/VideoRecordingManager.swift`: Hardware video encoding and buffer management
- `BroadcastExtension/VisionProcessor.swift`: OCR with landscape ROI optimization for COD Mobile
- `Shared/Models/TowerEvent.swift`: App Groups communication models

**Data Flow:**
```
ReplayKit Frame (Extension)
    ├→ Hardware Video Encoder (AVAssetWriter) → 10s Buffer
    └→ Cropped OCR (every 10th) → Kill Detection
                                        ↓
                            Save Video + Notify Main App
                                        ↓
                            Main App Updates Web UI
```

🔄 **Complete Workflow:**

1. **User starts screen recording with extension**
2. **Extension broadcastStarted() triggers**
3. **Extension starts hardware video encoding (AVAssetWriter)**
4. **Extension processes every frame:**
   - ALL frames → Hardware H.264 encoder → Rolling 10s buffer
   - Every 10th frame → Cropped OCR → Kill detection
5. **When kill detected:**
   - Extension saves current buffer as MP4
   - Extension notifies main app via App Groups
6. **Main app updates web UI with new video**

**App Groups Communication:**
- Uses: `group.com.clashmonitor.shared2`
- Extension saves videos to: `App Groups/Documents/COD_Kill_*.mp4`
- Extension writes kill notifications (keys: `killDetectedAt`, `shouldSaveHighlight`)
- Main app polls every 0.5 seconds for UI updates
- Videos stored in shared container accessible by both processes

### Critical Kill Detection Implementation

**COOLDOWN PATTERN (Essential):**
```swift
// ✅ CORRECT: Cooldown prevents OCR processing
private func processFrameForKillDetection(_ sampleBuffer: CMSampleBuffer) {
    guard !killDetected else { return } // Skip OCR during cooldown
    // ... OCR processing
}

// ❌ WRONG: Cooldown only in video save (OCR still runs)
private func triggerVideoSave() {
    guard !killDetected else { return } // Too late - OCR already processed
}
```

**Why This Matters:**
- Kill notifications can persist on screen for 1-3 seconds
- Without proper cooldown, same kill triggers multiple detections
- OCR processing during cooldown wastes CPU/memory
- Proper cooldown: `killDetected = true` → Skip OCR → Reset after 2s

## Critical Constraints

### Broadcast Extension Limitations
- **50MB memory hard limit** (iOS enforced)
- No network access allowed
- Limited background processing time
- Must use App Groups for data sharing

**FORBIDDEN PATTERNS:**
- ❌ NEVER use RPScreenRecorder in main app (conflicts with extension)
- ❌ NEVER buffer video frames in memory (use AVAssetWriter streaming)
- ❌ NEVER process full frames for OCR (always crop first)
- ❌ NEVER use excessive logging (causes memory crashes)
- ❌ NEVER implement cooldown only in video save logic (must be in OCR detection)

**MEMORY MANAGEMENT INSIGHTS:**
- **Hardware encoding doesn't buffer frames** - AVAssetWriter streams directly to disk
- **Cropped OCR reduces memory by 94%** - Process 600x200 instead of full frame
- **Single ReplayKit instance** - One capture for both video and OCR
- **Memory breakdown**: ~10MB (encoder) + ~5MB (OCR) + ~10MB (ReplayKit) = ~25MB total

### ReplayKit Buffer Management
- **NEVER hold references to CVPixelBuffer from CMSampleBuffer**
- ReplayKit has limited buffer pool (~8 buffers)
- Always copy pixel data immediately: `Data(bytes: address, count: dataSize)`
- Storing CVPixelBuffer references prevents ReplayKit from recycling its buffer pool

## Configuration Requirements

### App Groups Setup
1. Add "App Groups" capability to both main app and broadcast extension
2. Use identifier: `group.com.clashmonitor.shared2`
3. Update code references in:
   - `Shared/Models/TowerEvent.swift`: Update `appGroupIdentifier`
   - `BroadcastPickerView.swift`: Update `preferredExtension` bundle identifier

### Bundle Identifiers
- Main app: Update as needed (e.g., `com.yourname.clashmonitor`)
- Extension: Must match main app + `.BroadcastExtension`

### Signing & Capabilities
- Physical device required for testing
- App Groups capability required for both targets
- Screen Recording entitlement handled by ReplayKit framework

## Key Technologies

- **ReplayKit**: Screen recording and broadcast extension framework
- **Vision Framework**: OCR text recognition for kill detection
- **AVFoundation**: Hardware H.264 video encoding
- **WKWebView**: Web-based UI hosting with JavaScript bridge
- **SwiftUI + MVVM**: Modern declarative UI with ViewModels (legacy views)
- **Core Data**: Local persistence with app groups
- **App Groups**: Inter-process communication between main app and extension
- **UserNotifications**: Local notifications for kill events

## Development Workflow

### Setting up the Project
1. Open `ClashRoyaleMonitor.xcodeproj` in Xcode
2. Update bundle identifiers for both main app and extension
3. Configure App Groups capability with `group.com.clashmonitor.shared2`
4. Update code references to match your bundle identifiers
5. Test on physical device (ReplayKit requires hardware)

### Testing Strategy
- **Unit Tests**: XCTest framework for business logic
- **Integration Tests**: Test App Groups communication
- **Performance Tests**: Monitor extension memory usage (must stay under 50MB)
- **Real-world Testing**: Test with COD Mobile gameplay for kill detection accuracy

## File Structure

```
ClashRoyaleMonitor/
├── Main App/
│   ├── App/ (SwiftUI app lifecycle)
│   ├── Services/ (VideoRecordingManager, NotificationManager)
│   ├── ViewModels/ (MVVM pattern)
│   └── Views/ (SwiftUI interface)
├── BroadcastExtension/
│   ├── SampleHandler.swift (Main extension logic)
│   ├── VisionProcessor.swift (OCR processing)
│   └── PerformanceMonitor.swift (Memory tracking)
├── Shared/
│   └── Models/ (TowerEvent, App Groups constants)
└── Tests/ (Unit and UI tests)
```

## Performance Considerations

- Extension encodes EVERY frame for smooth video (hardware accelerated)
- Extension processes every 10th frame for OCR (cropped to save memory)
- Hardware H.264 encoding runs at 4 Mbps (reduced for memory efficiency)
- Rolling 10-second buffer auto-restarts to prevent accumulation
- Cropping OCR region saves 94% memory (600x200 vs 1920x1080)
- Single ReplayKit instance serves both video and OCR functions

## Web-Based UI Implementation (August 2025)

**Architecture**: Replaced native SwiftUI with web-based HTML/CSS/JavaScript interface hosted in WKWebView.

**Key Web UI Files:**
- `ClashRoyaleMonitor/Resources/WebUI/index.html`: Main interface structure
- `ClashRoyaleMonitor/Resources/WebUI/styles.css`: COD Mobile Battle Royale themed styling
- `ClashRoyaleMonitor/Resources/WebUI/app.js`: JavaScript functionality and native bridge
- `ClashRoyaleMonitor/App/ClashRoyaleMonitorApp.swift`: WKWebView host with WebViewController

**JavaScript Bridge Communication:**
```javascript
// Web to Native
window.webkit.messageHandlers.iosApp.postMessage({
    action: 'startMonitoring', data: {}
});

// Native to Web (via evaluateJavaScript)
window.updateKillCount(newCount);
```

**Web UI Features:**
- Real-time kill/death statistics with session tracking
- Video highlight management and playback
- Military-themed UI with cyan/blue color scheme (#00d4ff, #00ff88, #ff6b6b)
- Responsive design optimized for mobile devices
- Native integration for file system access and app state management

## Privacy & Security

- All video processing happens locally on device
- No screen content is stored or transmitted externally
- Statistics stored locally using Core Data with App Groups
- No external analytics, tracking, or cloud services
- BLE communication (if applicable) uses standard pairing/encryption

## iOS Platform Limitations

### ReplayKit Constraints
- **Only ONE ReplayKit session allowed system-wide** - Extension OR main app, not both
- **No screen capture API outside ReplayKit on iOS** - AVCaptureScreenInput doesn't exist
- **Extension limited to 50MB memory** - Hard iOS limit, app terminated if exceeded
- **Solution**: Extension handles both video encoding and OCR using single ReplayKit instance

### Memory Optimization Techniques
1. **Crop before OCR**: Reduces memory usage by 94%
2. **Hardware encoding**: AVAssetWriter streams to disk, no buffering
3. **Reduced bitrate**: 4 Mbps instead of 8 Mbps
4. **Minimal logging**: Prevents memory accumulation
5. **Frame sampling**: OCR only every 10th frame

### Key Success Factors
- Extension handles both functions with one ReplayKit instance
- Every frame encoded, every 10th frame analyzed
- Cropping + hardware acceleration keeps memory under 25MB
- Direct-to-disk encoding prevents memory accumulation