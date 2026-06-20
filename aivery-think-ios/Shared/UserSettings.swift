import SwiftUI
import Combine

final class UserSettings: ObservableObject {
    @AppStorage("agentId") var agentId: String = "default"
    @AppStorage("showThinking") var showThinking: Bool = true
    @AppStorage("enableReasoning") var enableReasoning: Bool = false
    @AppStorage("colorScheme") var colorScheme: String = "system"
    // Motion / visual effects — also auto-suppressed under system Reduce Motion.
    @AppStorage("showPlexus") var showPlexus: Bool = true
    @AppStorage("plexusMemoryEffects") var plexusMemoryEffects: Bool = true

    static let shared = UserSettings()

    var resolvedColorScheme: ColorScheme? {
        switch colorScheme {
        case "dark":  return .dark
        case "light": return .light
        default:      return nil  // nil = follow system
        }
    }
}
