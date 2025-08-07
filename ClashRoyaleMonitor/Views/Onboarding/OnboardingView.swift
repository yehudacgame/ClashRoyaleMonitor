import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @State private var currentPage = 0
    
    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                // Welcome Page
                OnboardingPage(
                    imageName: "gamecontroller.fill",
                    title: "Welcome to ClashRoyale Monitor",
                    description: "Get instant notifications when towers are destroyed in your Clash Royale matches",
                    showButton: false
                )
                .tag(0)
                
                // How it Works
                OnboardingPage(
                    imageName: "antenna.radiowaves.left.and.right",
                    title: "Real-Time Monitoring",
                    description: "We use screen recording to detect tower destruction events and notify you instantly",
                    showButton: false
                )
                .tag(1)
                
                // Privacy
                OnboardingPage(
                    imageName: "lock.shield.fill",
                    title: "Your Privacy Matters",
                    description: "Screen content is processed locally on your device. Nothing is stored or transmitted.",
                    showButton: false
                )
                .tag(2)
                
                // Setup
                OnboardingSetupPage()
                    .tag(3)
            }
            .tabViewStyle(PageTabViewStyle())
            .indexViewStyle(PageIndexViewStyle(backgroundDisplayMode: .always))
            
            // Navigation Buttons
            HStack {
                if currentPage > 0 {
                    Button("Previous") {
                        withAnimation {
                            currentPage -= 1
                        }
                    }
                    .foregroundColor(.blue)
                }
                
                Spacer()
                
                if currentPage < 3 {
                    Button("Next") {
                        withAnimation {
                            currentPage += 1
                        }
                    }
                    .foregroundColor(.blue)
                }
            }
            .padding()
        }
    }
}

struct OnboardingPage: View {
    let imageName: String
    let title: String
    let description: String
    let showButton: Bool
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: imageName)
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            VStack(spacing: 16) {
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
    }
}

struct OnboardingSetupPage: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notificationManager: NotificationManager
    @State private var notificationsEnabled = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.green)
            
            Text("Let's Get Started!")
                .font(.title)
                .fontWeight(.bold)
            
            VStack(spacing: 20) {
                // Notification Permission
                PermissionRow(
                    iconName: "bell.fill",
                    title: "Enable Notifications",
                    description: "Get alerts when towers are destroyed",
                    isEnabled: notificationsEnabled,
                    action: {
                        notificationManager.requestAuthorization()
                        notificationsEnabled = true
                    }
                )
                
                // Complete Setup
                Button(action: completeOnboarding) {
                    Text("Start Monitoring")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation {
            appState.showOnboarding = false
        }
    }
}

struct PermissionRow: View {
    let iconName: String
    let title: String
    let description: String
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(isEnabled ? .green : .blue)
                .frame(width: 40)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !isEnabled {
                Button("Enable") {
                    action()
                }
                .foregroundColor(.blue)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .environmentObject(NotificationManager())
}