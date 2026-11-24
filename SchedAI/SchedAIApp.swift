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
    @StateObject private var semester = SemesterStore()

    var body: some Scene {
        WindowGroup {
            LogoLaunchView()
                .environmentObject(app)
                .environmentObject(subscriptions)
                .environmentObject(semester)
                .onAppear { connectSemesterToScheduler() }
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

    /// Classes block time: the scheduler asks the semester for class meetings
    /// on every day it plans.
    private func connectSemesterToScheduler() {
        let semester = self.semester
        app.additionalBusyIntervals = { day in
            MainActor.assumeIsolated { semester.classIntervals(on: day) }
        }
        #if DEBUG
        DebugFixtures.applyLaunchArguments(app: app, semester: semester)
        #endif
    }
}
