import SwiftUI
import Combine

final class UserSettings: ObservableObject {
    @AppStorage("showThinking") var showThinking: Bool = true
    @AppStorage("enableReasoning") var enableReasoning: Bool = false
    @AppStorage("colorScheme") var colorScheme: String = "system"
    // Motion / visual effects — also auto-suppressed under system Reduce Motion.
    @AppStorage("showPlexus") var showPlexus: Bool = true
    @AppStorage("plexusMemoryEffects") var plexusMemoryEffects: Bool = true

    static let shared = UserSettings()

    /// Any vibrant AiVery theme — the bright OG ("aivery") or the darker navy
    /// "Galaxy" ("galaxy"). Drives the shared treatment: white plexus, blue user
    /// bubbles, amber interactive accent. Both ride on a dark base.
    var isAivery: Bool { colorScheme == "aivery" || colorScheme == "galaxy" }

    /// The darker navy "AiVery Galaxy" variant (vs. the bright OG "AiVery"). Only the
    /// chat background differs; everything else is shared via `isAivery`.
    var isGalaxy: Bool { colorScheme == "galaxy" }

    var resolvedColorScheme: ColorScheme? {
        switch colorScheme {
        case "dark":             return .dark
        case "light":            return .light
        case "aivery", "galaxy": return .dark   // vibrant themes sit on a dark base
        default:                 return nil      // nil = follow system
        }
    }
}
