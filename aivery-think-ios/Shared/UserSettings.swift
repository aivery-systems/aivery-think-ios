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

    /// The "AiVery" theme: vibrant rotating violet→blue→teal gradient, white plexus,
    /// blue user bubbles. Rides on a dark base so system chrome/text stays legible.
    var isAivery: Bool { colorScheme == "aivery" }

    var resolvedColorScheme: ColorScheme? {
        switch colorScheme {
        case "dark":   return .dark
        case "light":  return .light
        case "aivery": return .dark   // vibrant theme sits on a dark base
        default:       return nil      // nil = follow system
        }
    }
}
