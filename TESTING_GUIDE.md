# ClashRoyale Monitor - Testing Guide

## Quick Deployment Steps

### 1. Build & Install
1. Open `ClashRoyaleMonitor.xcodeproj` in Xcode
2. Select your iPhone device (not simulator)
3. Clean: **Product → Clean Build Folder** (⌘+⇧+K)
4. Build: **Product → Build** (⌘+B)
5. Run: **Product → Run** (⌘+R)

### 2. App Setup
1. Allow notification permissions when prompted
2. Complete onboarding flow
3. Navigate to Dashboard

### 3. Screen Recording Setup
1. Go to **Control Center** on your iPhone
2. Add **Screen Recording** if not already added:
   - Settings → Control Center → Add Screen Recording
3. Long press the Screen Recording button
4. Select **ClashRoyale Monitor** from the app list
5. Tap **Start Broadcast**

## Testing Scenarios

### Basic Functionality Test
1. **Start monitoring**: Enable screen recording with the app
2. **Open any app** with text (Notes, Safari, etc.)
3. **Check Console output**: Should see OCR results in Xcode console
4. **Stop monitoring**: Stop screen recording

### Tower Detection Test

#### Test Case 1: Simulated Text
1. Start monitoring
2. Open **Notes app**
3. Type and display on screen:
   - "You Tower Destroyed"
   - "Enemy Tower Destroyed" 
   - "King Tower destroyed"
4. Check for notifications

#### Test Case 2: Clash Royale Gameplay (Real Test)
1. Install Clash Royale from App Store
2. Start monitoring with our app
3. Play a match in Clash Royale
4. Observe notifications when towers are destroyed

#### Test Case 3: YouTube Video Test (Spoofing Test)
1. Start monitoring
2. Go to YouTube
3. Search for "Clash Royale tower destroyed"
4. Play a video in fullscreen
5. Should NOT trigger false notifications (if anti-spoofing works)

## Expected Behaviors

### ✅ Success Indicators
- App launches without crashes
- Screen recording starts successfully
- OCR text appears in Xcode console
- Notifications appear for tower destruction events
- App stops monitoring when screen recording stops

### ❌ Failure Indicators
- App crashes on launch
- Screen recording fails to start
- No OCR output in console
- False positive notifications
- App doesn't stop monitoring properly

## Debugging

### Console Output
Monitor Xcode console for:
```
🟦🟦🟦 OCR_RESULT: [detected text]
🔍 TowerDetector: Analyzing text: [...]
🎯 TowerDetector: Created tower event: [...]
```

### Common Issues
1. **No OCR Output**: Check screen recording permissions
2. **False Positives**: Adjust detection keywords in TowerDetector.swift
3. **App Crashes**: Check memory usage and Core Data setup
4. **No Notifications**: Verify notification permissions

## Performance Monitoring

### Resource Usage
- Monitor CPU usage during screen recording
- Check memory consumption
- Battery drain testing (run for 30+ minutes)

### Frame Processing
- Current setting: Process every 10th frame (~3 FPS)
- Adjust `frameInterval` in SampleHandler.swift if needed

## Test Results Log

Document your findings:

| Test | Result | Notes |
|------|--------|-------|
| App Launch | ✅/❌ | |
| Screen Recording | ✅/❌ | |
| OCR Detection | ✅/❌ | |
| Tower Detection | ✅/❌ | |
| Notifications | ✅/❌ | |
| Performance | ✅/❌ | |

## Next Steps After Testing

Based on test results:
1. **If successful**: Proceed with more advanced features
2. **If issues found**: Debug and fix core functionality first
3. **Performance problems**: Optimize frame processing rate
4. **False positives**: Implement anti-spoofing measures

## Quick Fixes

### Build Issues
```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData/*

# Reset simulator
xcrun simctl erase all
```

### Permission Issues
- Reset iOS permissions: Settings → General → Reset → Reset Location & Privacy