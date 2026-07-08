//
//  aivery_think_iosApp.swift
//  aivery-think-ios
//
//  Created by Christian Matsoukis on 6/12/26.
//

import SwiftUI

@main
struct aivery_think_iosApp: App {
    @State private var isSignedIn = false
    @StateObject private var settings = UserSettings.shared
    // Touch at startup so the UNUserNotificationCenterDelegate is registered before any notification fires.
    private let _notif = NotificationManager.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if isSignedIn {
                    ContentView(isSignedIn: $isSignedIn)
                } else {
                    APIKeyEntryView(isSignedIn: $isSignedIn)
                }
            }
            // Theme-aware tint: drives the text-input caret and all control accents.
            // AiVery gets high-contrast amber (system blue vanishes into its gradient).
            .tint(settings.isAivery ? Color.aiveryAccent : Color.accentColor)
            .preferredColorScheme(settings.resolvedColorScheme)
            .onAppear {
                if APIClient.shared.restoreApiKey() {
                    isSignedIn = true
                }
            }
        }
    }
}
