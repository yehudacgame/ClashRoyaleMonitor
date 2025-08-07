import SwiftUI

struct SettingsView: View {
    @AppStorage("notificationSound") private var notificationSound = "default"
    @AppStorage("detectionSensitivity") private var detectionSensitivity = 0.5
    @AppStorage("cooldownPeriod") private var cooldownPeriod = 5.0
    @AppStorage("preferredLanguage") private var preferredLanguage = "en"
    @State private var showingResetAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                // Notification Settings
                Section(header: Text("Notifications")) {
                    Picker("Sound", selection: $notificationSound) {
                        Text("Default").tag("default")
                        Text("Chime").tag("chime")
                        Text("Alert").tag("alert")
                        Text("Victory").tag("victory")
                        Text("Defeat").tag("defeat")
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Cooldown Period")
                        Text("\(Int(cooldownPeriod)) seconds")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $cooldownPeriod, in: 3...10, step: 1)
                    }
                }
                
                // Detection Settings
                Section(header: Text("Detection")) {
                    VStack(alignment: .leading) {
                        Text("Sensitivity")
                        HStack {
                            Text("Low")
                                .font(.caption)
                            Slider(value: $detectionSensitivity, in: 0...1)
                            Text("High")
                                .font(.caption)
                        }
                    }
                    
                    Picker("Language", selection: $preferredLanguage) {
                        Text("English").tag("en")
                        Text("Spanish").tag("es")
                        Text("French").tag("fr")
                    }
                }
                
                // App Information
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    
                    Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                    
                    Link("Support", destination: URL(string: "mailto:support@clashmonitor.app")!)
                }
                
                // Data Management
                Section(header: Text("Data")) {
                    Button("Reset Statistics") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.red)
                    
                    Button("Clear Cache") {
                        clearCache()
                    }
                }
                
                // Debug Section
                #if DEBUG
                Section(header: Text("Debug")) {
                    Button("Test Notification") {
                        sendTestNotification()
                    }
                    
                    Button("Generate Sample Data") {
                        generateSampleData()
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .alert("Reset Statistics", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    resetStatistics()
                }
            } message: {
                Text("This will permanently delete all your statistics. This action cannot be undone.")
            }
        }
    }
    
    private func clearCache() {
        // Clear any cached data
        let sharedDefaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
        sharedDefaults?.removeObject(forKey: "currentSessionId")
    }
    
    private func resetStatistics() {
        PersistenceController.shared.deleteAllData()
        
        // Also clear shared defaults
        let sharedDefaults = UserDefaults(suiteName: SharedConstants.appGroupIdentifier)
        sharedDefaults?.removeObject(forKey: "currentSessionId")
    }
    
    private func sendTestNotification() {
        let event = TowerEvent(
            timestamp: Date(),
            towerType: .princess,
            isPlayerTower: false,
            sessionId: UUID()
        )
        
        NotificationManager().sendTowerNotification(event: event)
    }
    
    private func generateSampleData() {
        // Generate sample sessions and events for testing
        let persistenceController = PersistenceController.shared
        
        for i in 0..<5 {
            let session = persistenceController.createSession()
            session.startTime = Date().addingTimeInterval(TimeInterval(-i * 86400))
            session.endTime = session.startTime?.addingTimeInterval(TimeInterval(1800))
            
            // Add some tower events to this session
            for j in 0..<Int.random(in: 1...5) {
                _ = persistenceController.createTowerEvent(
                    session: session,
                    towerType: [.king, .princess].randomElement()!,
                    isPlayerTower: Bool.random()
                )
            }
        }
    }
}

#Preview {
    SettingsView()
}