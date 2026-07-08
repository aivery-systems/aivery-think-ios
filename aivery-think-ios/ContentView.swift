import SwiftUI

private let sessionTimeoutKey = "lastActiveAt"
private let sessionTimeout: TimeInterval = 30 * 60  // 30 minutes

struct ContentView: View {
    @Binding var isSignedIn: Bool
    @StateObject private var chatVM = ChatViewModel()
    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Chat", systemImage: "bubble.left.and.text.bubble.right", value: 0) {
                ChatView(vm: chatVM)
            }
            Tab("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90", value: 1) {
                ConversationsView(chatVM: chatVM, selectedTab: $selectedTab)
            }
            Tab("Memories", systemImage: "brain.head.profile", value: 2) {
                MemoryBrowserView()
            }
            Tab("Settings", systemImage: "gearshape", value: 3) {
                SettingsView(isSignedIn: $isSignedIn)
            }
        }
        .ignoresSafeArea(.keyboard)
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .background, .inactive:
                UserDefaults.standard.set(Date(), forKey: sessionTimeoutKey)
            case .active:
                let last = UserDefaults.standard.object(forKey: sessionTimeoutKey) as? Date
                if let last, Date().timeIntervalSince(last) > sessionTimeout {
                    chatVM.startNewChat()
                }
            @unknown default:
                break
            }
        }
    }
}
