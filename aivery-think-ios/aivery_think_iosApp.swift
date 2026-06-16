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

    var body: some Scene {
        WindowGroup {
            Group {
                if isSignedIn {
                    ContentView(isSignedIn: $isSignedIn)
                } else {
                    APIKeyEntryView(isSignedIn: $isSignedIn)
                }
            }
            .tint(Color.accentColor)
            .preferredColorScheme(settings.resolvedColorScheme)
            .onAppear {
                if APIClient.shared.restoreApiKey() {
                    isSignedIn = true
                }
            }
        }
    }
}
