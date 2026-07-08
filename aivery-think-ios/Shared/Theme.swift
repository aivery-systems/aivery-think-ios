import SwiftUI

/// Aivery brand palette — the single source of truth for the colors that used to be
/// scattered as raw Color(red:green:blue:) literals across the chat views and widgets.
///
/// NOTE: like Shared/ThinkingActivityAttributes.swift, this file is a member of BOTH the
/// app target AND the ThinkWidgetsExtension target (via a membership exception in
/// project.pbxproj) — the Live Activity UI uses the same palette.
extension Color {
    /// Interactive accent for the AiVery theme — icons, input caret, send button, toggles.
    /// Amber, matching the plexus memory-ripple gold. Deliberately NOT the brand teal:
    /// teal sits on the blue↔green confusion axis (invisible distinction for blue–green
    /// color-deficient vision) and both hues live inside the theme's violet→blue→teal
    /// gradient. Amber differs from every gradient stop in hue AND luminance, so the
    /// controls stay legible even in grayscale.
    static let aiveryAccent = Color(red: 1, green: 200/255, blue: 50/255) // #FFC832

    /// Brand teal — user bubbles (dark mode), agent "remember" action lines,
    /// thinking-brain icon (dark mode), background orb glow. Matches the web
    /// client's --bubble-user (globals.css).
    static let aiveryTeal = Color(red: 76/255, green: 201/255, blue: 167/255) // #4CC9A7

    /// Brand violet — user bubbles (light mode), agent "note" action lines,
    /// thinking-brain icon (light mode), plexus shimmer on the AiVery theme.
    static let aiveryViolet = Color(red: 185/255, green: 167/255, blue: 255/255) // #B9A7FF

    /// AiVery-theme blue — user bubbles and the middle stop of the theme gradient,
    /// matching the app icon.
    static let aiveryBlue = Color(red: 59/255, green: 130/255, blue: 242/255) // #3B82F2
}
