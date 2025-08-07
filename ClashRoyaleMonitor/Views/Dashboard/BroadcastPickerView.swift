import SwiftUI
import ReplayKit

struct BroadcastPickerView: View {
    let onCompletion: (Bool) -> Void
    @State private var showingInstructions = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if showingInstructions {
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Start Screen Recording")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("To monitor Clash Royale, we need to record your screen. Follow these steps:")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            InstructionRow(number: 1, text: "Tap the button below")
                            InstructionRow(number: 2, text: "Select 'ClashRoyale Monitor' from the list")
                            InstructionRow(number: 3, text: "Tap 'Start Broadcast'")
                        }
                        
                        Spacer()
                        
                        // Debug: Regular button that should work
                        Button("TEST: Regular Button") {
                            print("🎯 Regular button was tapped!")
                            NSLog("🎯 Regular button was tapped!")
                        }
                        .frame(height: 50)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        
                        // Broadcast Picker Button
                        BroadcastPickerButton()
                            .frame(height: 60)
                        
                        Text("Your screen content is processed locally and never stored or transmitted.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top)
                    }
                    .padding()
                } else {
                    // Success View
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.green)
                        
                        Text("Recording Started!")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("You can now launch Clash Royale and start playing. We'll notify you when towers are destroyed.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Done") {
                            onCompletion(true)
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                }
            }
            .navigationBarItems(trailing: Button("Cancel") {
                onCompletion(false)
            })
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("BroadcastStarted"))) { _ in
            withAnimation {
                showingInstructions = false
            }
        }
    }
}

struct InstructionRow: View {
    let number: Int
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
                .font(.body)
        }
    }
}

// MARK: - Broadcast Picker Button
struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        print("🔍 BroadcastPickerButton: Creating makeUIView")
        NSLog("🔍 BroadcastPickerButton: Creating makeUIView - NSLog version")
        
        let containerView = UIView()
        containerView.backgroundColor = UIColor.systemBlue
        containerView.layer.cornerRadius = 12
        containerView.clipsToBounds = true
        containerView.isUserInteractionEnabled = true
        
        // Add tap gesture to container for debugging
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(BroadcastPickerCoordinator.containerTapped))
        containerView.addGestureRecognizer(tapGesture)
        
        print("🔍 BroadcastPickerButton: Container view created with userInteraction: \(containerView.isUserInteractionEnabled)")
        NSLog("🔍 BroadcastPickerButton: Container view created with userInteraction: %@", containerView.isUserInteractionEnabled ? "true" : "false")
        
        let picker = RPSystemBroadcastPickerView()
        picker.preferredExtension = "com.clashmonitor.app2.BroadcastExtension2"
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear
        picker.isUserInteractionEnabled = true
        
        print("🔍 BroadcastPickerButton: Picker created with preferredExtension: \(picker.preferredExtension ?? "nil")")
        print("🔍 BroadcastPickerButton: Picker userInteraction: \(picker.isUserInteractionEnabled)")
        
        // Add picker to container
        picker.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(picker)
        
        NSLayoutConstraint.activate([
            picker.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            picker.topAnchor.constraint(equalTo: containerView.topAnchor),
            picker.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        print("🔍 BroadcastPickerButton: Constraints activated")
        
        // Store references in coordinator
        context.coordinator.picker = picker
        context.coordinator.container = containerView
        
        // Customize the button appearance with multiple attempts
        DispatchQueue.main.async {
            context.coordinator.customizeButton(attempt: 1)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            context.coordinator.customizeButton(attempt: 2)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            context.coordinator.customizeButton(attempt: 3)
        }
        
        return containerView
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        print("🔍 BroadcastPickerButton: updateUIView called")
        if let picker = uiView.subviews.first as? RPSystemBroadcastPickerView {
            context.coordinator.picker = picker
            context.coordinator.customizeButton(attempt: 0)
        }
    }
    
    func makeCoordinator() -> BroadcastPickerCoordinator {
        BroadcastPickerCoordinator()
    }
}

// MARK: - Coordinator
class BroadcastPickerCoordinator: NSObject {
    var picker: RPSystemBroadcastPickerView?
    var container: UIView?
    
    @objc func containerTapped() {
        print("🎯 BroadcastPickerButton: Container was tapped!")
        NSLog("🎯 BroadcastPickerButton: Container was tapped!")
        
        // Try to programmatically trigger the picker
        if let picker = picker {
            print("🔍 BroadcastPickerButton: Trying to find and trigger button...")
            NSLog("🔍 BroadcastPickerButton: Trying to find and trigger button...")
            for subview in picker.subviews {
                if let button = subview as? UIButton {
                    print("🔍 BroadcastPickerButton: Found button, sending touchUpInside event")
                    NSLog("🔍 BroadcastPickerButton: Found button, sending touchUpInside event")
                    button.sendActions(for: .touchUpInside)
                    break
                }
            }
        }
    }
    
    @objc func buttonTapped() {
        print("🎯 BroadcastPickerButton: Button was tapped!")
        NSLog("🎯 BroadcastPickerButton: Button was tapped!")
    }
    
    @objc func buttonTouchDown() {
        print("🎯 BroadcastPickerButton: Button touch down detected!")
        NSLog("🎯 BroadcastPickerButton: Button touch down detected!")
    }
    
    func customizeButton(attempt: Int) {
        guard let picker = picker else {
            print("🔍 BroadcastPickerButton: No picker available for customization")
            return
        }
        
        print("🔍 BroadcastPickerButton: Customizing button (attempt \(attempt))")
        print("🔍 BroadcastPickerButton: Picker has \(picker.subviews.count) subviews")
        
        for (index, subview) in picker.subviews.enumerated() {
            print("🔍 BroadcastPickerButton: Subview \(index): \(type(of: subview)) - userInteraction: \(subview.isUserInteractionEnabled)")
            
            if let button = subview as? UIButton {
                print("🔍 BroadcastPickerButton: Found UIButton! Customizing...")
                print("🔍 BroadcastPickerButton: Button enabled: \(button.isEnabled)")
                print("🔍 BroadcastPickerButton: Button userInteraction: \(button.isUserInteractionEnabled)")
                print("🔍 BroadcastPickerButton: Button current title: \(button.title(for: .normal) ?? "nil")")
                
                button.setTitle("Start Screen Recording", for: .normal)
                button.setTitleColor(.white, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
                button.backgroundColor = .clear
                button.setImage(nil, for: .normal)
                button.isUserInteractionEnabled = true
                button.isEnabled = true
                
                // Add debug target actions
                button.removeTarget(nil, action: nil, for: .allEvents)
                button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
                button.addTarget(self, action: #selector(buttonTouchDown), for: .touchDown)
                
                print("🔍 BroadcastPickerButton: Button customization complete")
                break
            }
        }
        
        // Also check all nested subviews recursively
        func findAllButtons(in view: UIView, level: Int = 0) {
            let indent = String(repeating: "  ", count: level)
            print("🔍 BroadcastPickerButton: \(indent)Checking \(type(of: view))")
            
            if let button = view as? UIButton {
                print("🔍 BroadcastPickerButton: \(indent)Found nested button: \(button)")
                button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
            }
            
            for subview in view.subviews {
                findAllButtons(in: subview, level: level + 1)
            }
        }
        
        findAllButtons(in: picker)
    }
}

#Preview {
    BroadcastPickerView { _ in }
}