# ClashRoyale Tower Monitor

An iOS companion app that monitors Clash Royale gameplay in real-time using screen recording technology to detect tower destruction events and provide instant notifications.

## Features

- 🎮 **Real-time Monitoring**: Detects tower destruction events during Clash Royale matches
- 🔔 **Instant Notifications**: Get notified immediately when towers are destroyed
- 📊 **Statistics Tracking**: Track your performance across gaming sessions
- 🛡️ **Privacy Focused**: All processing happens locally on your device
- 📱 **iOS 14.0+**: Built with SwiftUI and modern iOS technologies

## Setup Instructions

### Requirements
- Xcode 13.0 or later
- iOS 14.0+ deployment target
- Apple Developer account (for device testing)

### Project Setup

1. **Open the Project**
   ```bash
   cd ClashRoyaleMonitor
   open ClashRoyaleMonitor.xcodeproj
   ```

2. **Configure Signing**
   - Select the ClashRoyaleMonitor target
   - Go to Signing & Capabilities
   - Select your development team
   - Update bundle identifier if needed (e.g., `com.yourname.clashmonitor`)

3. **Configure App Groups**
   - In Signing & Capabilities, add "App Groups" capability
   - Create a new app group: `group.com.yourname.clashmonitor.shared`
   - Add the same app group to both the main app and broadcast extension targets

4. **Configure Broadcast Extension**
   - Select the BroadcastExtension target
   - Update bundle identifier (e.g., `com.yourname.clashmonitor.BroadcastExtension`)
   - Ensure the same development team is selected

5. **Update Code References**
   - In `Shared/Models/TowerEvent.swift`, update the app group identifier:
     ```swift
     static let appGroupIdentifier = "group.com.yourname.clashmonitor.shared"
     ```
   - In `BroadcastPickerView.swift`, update the preferred extension:
     ```swift
     picker.preferredExtension = "com.yourname.clashmonitor.BroadcastExtension"
     ```

### Building and Running

1. Select your target device (physical device recommended for broadcast extension)
2. Build and run the project (⌘R)
3. Allow notification permissions when prompted
4. Complete the onboarding process
5. Start monitoring by enabling screen recording

### Testing

1. Launch the app and complete setup
2. Tap "Launch Clash Royale" or open the game manually
3. Start screen recording via Control Center
4. Select "ClashRoyale Monitor" from the broadcast options
5. Play a match and watch for notifications when towers are destroyed

## Architecture

```
ClashRoyaleMonitor/
├── Main App
│   ├── SwiftUI Views
│   ├── View Models
│   ├── Services (Notifications, Game Integration)
│   └── Models
├── Broadcast Extension
│   ├── SampleHandler (Screen capture)
│   ├── VisionProcessor (OCR)
│   └── TowerDetector (Event detection)
└── Shared
    ├── Models (TowerEvent, GameSession)
    └── Utilities
```

## Key Technologies

- **ReplayKit**: Screen recording and broadcast extension
- **Vision Framework**: Text recognition for game events
- **SwiftUI**: Modern declarative UI
- **UserNotifications**: Local notifications
- **App Groups**: Data sharing between app and extension

## Privacy

- All video processing happens locally on device
- No screen content is stored or transmitted
- Statistics are stored locally using Core Data
- No external analytics or tracking

## Known Limitations

- Broadcast extensions have a 50MB memory limit
- Processing is limited to maintain performance
- Detection accuracy depends on screen resolution and game UI

## Future Enhancements

- Machine learning for improved detection accuracy
- Support for more game events (elixir tracking, card usage)
- Cloud sync for statistics across devices
- Social features for sharing stats with friends

## License

This project is for educational purposes. Clash Royale is a trademark of Supercell.