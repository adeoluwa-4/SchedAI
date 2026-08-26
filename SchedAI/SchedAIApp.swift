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
    @StateObject private var subscriptions = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            LogoLaunchView()
                .environmentObject(app)
                .environmentObject(subscriptions)
                // Default = System. If the user overrides in Settings, app.theme changes it.
                .preferredColorScheme(app.theme.colorScheme)
                .sheet(item: $subscriptions.presentedPaywall) { context in
                    PaywallView(context: context)
                        .environmentObject(subscriptions)
                }
                .task {
                    await subscriptions.start()
                }
        }
    }
}
