//
//  SchedAIApp.swift
//  SchedAI
//
//  Created by Adeoluwa Adekoya on 9/5/25.
//

import SwiftUI

@main
struct SchedAIApp: App {
    @StateObject private var app = AppState()

    var body: some Scene {
        WindowGroup {
            LogoLaunchView()
                .environmentObject(app)
                // Default = System. If the user overrides in Settings, app.theme changes it.
                .preferredColorScheme(app.theme.colorScheme)
        }
    }
}
