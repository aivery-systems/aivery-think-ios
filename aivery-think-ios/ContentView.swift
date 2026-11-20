import SwiftUI

private let sessionTimeoutKey = "lastActiveAt"

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
            case .background:
                // Stamp only on .background — .inactive also fires on the way back to
                // .active (and for Control Center, app switcher), which re-stamped the
                // time and made the timeout fire inconsistently.
                UserDefaults.standard.set(Date(), forKey: sessionTimeoutKey)
            case .active:
                let last = UserDefaults.standard.object(forKey: sessionTimeoutKey) as? Date
                UserDefaults.standard.removeObject(forKey: sessionTimeoutKey)
                let settings = UserSettings.shared
                let timeout = TimeInterval(settings.autoNewChatTimeoutMinutes * 60)
                if settings.autoNewChatEnabled, let last, Date().timeIntervalSince(last) > timeout {
                    chatVM.startNewChat()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}
