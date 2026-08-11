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
            ChatView(vm: chatVM)
                .tabItem { Label("Chat", systemImage: "bubble.left.and.text.bubble.right") }
                .tag(0)
            ConversationsView(chatVM: chatVM, selectedTab: $selectedTab)
                .tabItem { Label("History", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") }
                .tag(1)
            MemoryBrowserView()
                .tabItem { Label("Memories", systemImage: "brain.head.profile") }
                .tag(2)
            SettingsView(isSignedIn: $isSignedIn)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)
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
