# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ClashRoyaleMonitor is an iOS app that uses ReplayKit and Vision Framework for real-time game monitoring and video highlight capture. Originally designed for Clash Royale tower detection, it has evolved into a COD Mobile kill detection system that automatically saves 10-second highlight videos when kills are detected.

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

**CRITICAL ARCHITECTURE RULES (August 2025):**

```
Extension (SampleHandler):              Main App (VideoRecordingManager):
Frame → OCR → "KILL/ELIMINATED"    →    RPScreenRecorder → Rolling 10s Buffer
     ↓                                         ↓
App Groups Notification           ←    Hardware H.264 Encoder → Save Highlight
     ↓                                         ↓
(Extension memory < 50MB)              Documents/COD_Kill_timestamp.mp4
```

**Extension Role (SampleHandler.swift):**
- ✅ Process frames for OCR text detection ONLY (every 10th frame)
- ✅ Detect "KILL", "ELIMINATED", "ELIMINA" with substring matching
- ✅ **NEVER store video frames** - process OCR and immediately discard
- ✅ Notify main app via App Groups when kill detected
- ✅ 2-second cooldown to prevent consecutive detections
- ✅ **CRITICAL: Cooldown prevents OCR processing, not just video saves**
- ✅ Memory stays under 50MB iOS limit

**Main App Role (VideoRecordingManager.swift):**
- ✅ Run `RPScreenRecorder.startCapture()` continuously in background thread
- ✅ Use `AVAssetWriter` with hardware H.264 encoding
- ✅ Maintain rolling 10-second buffer that auto-restarts
- ✅ Monitor App Groups for kill notifications (0.5s polling)
- ✅ Save buffer to Documents folder when triggered
- ✅ 3-second cooldown to prevent consecutive saves

### Key Components

**ReplayKit Architecture:**
- `BroadcastExtension/SampleHandler.swift`: OCR processing and kill detection
- `ClashRoyaleMonitor/Services/VideoRecordingManager.swift`: Hardware video encoding and buffer management
- `BroadcastExtension/VisionProcessor.swift`: OCR with landscape ROI optimization for COD Mobile
- `Shared/Models/TowerEvent.swift`: App Groups communication models

**Data Flow:**
```
RPScreenRecorder → Main App Rolling Buffer (10s) → Kill Triggered → Save MP4
                           ↑
App Groups ←  Kill Detection  ← OCR Processing ← Extension Frame Sample
```

**App Groups Communication:**
- Uses: `group.com.clashmonitor.shared2`
- Extension writes kill notifications
- Main app polls every 0.5 seconds
- Both UserDefaults and CFPreferences for reliability

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
- ❌ NEVER implement video encoding in the extension
- ❌ NEVER store video frames in SampleHandler
- ❌ NEVER use similarity matching (use substring matching instead)
- ❌ NEVER process every frame (sample every 10th frame)
- ❌ NEVER implement cooldown only in video save logic (must be in OCR detection)

**MEMORY MANAGEMENT INSIGHTS:**
- **NEVER store video frames/buffers in extension** - Each CMSampleBuffer consumes ~54MB
- **Extension should ONLY analyze frames, not store them** - Process for OCR and immediately discard
- **Architecture Rule**: Extension = Analysis Only, Main App = Storage Only

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
- **SwiftUI + MVVM**: Modern declarative UI with ViewModels
- **Core Data**: Local persistence with app groups
- **App Groups**: Inter-process communication between main app and extension

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

- Extension processes every 10th frame to balance detection speed vs memory usage
- Hardware H.264 encoding runs at 8 Mbps for quality video highlights
- Rolling buffer management prevents memory accumulation
- App Groups polling at 0.5s intervals for responsive kill detection
- Cooldown systems prevent spam detection and consecutive saves