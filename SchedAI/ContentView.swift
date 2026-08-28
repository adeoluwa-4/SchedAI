import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var selectedTab: Tab = .today
    @StateObject private var adMob = AdMobController()

    // Production banner unit. SchedAI Pro subscribers never request or render it.
    private let bannerAdUnitID = "ca-app-pub-1559067251456423/4837063087"

    private enum Tab: Hashable {
        case today
        case tasks
        case settings
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                TodayView()
                    .tag(Tab.today)
                    .tabItem { Label("Today", systemImage: "calendar.badge.clock") }

                TasksView()
                    .tag(Tab.tasks)
                    .tabItem { Label("Tasks", systemImage: "checkmark.circle") }

                SettingsView()
                    .tag(Tab.settings)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
            }

            if !subscriptions.isPro, adMob.canRequestAds {
                Divider()
                AdMobBannerView(adUnitID: bannerAdUnitID)
                    .background(Color(uiColor: .systemBackground))
                    .accessibilityLabel("Advertisement")
            }
        }
        .task(id: subscriptions.isPro) {
            guard !subscriptions.isPro else { return }
            await adMob.start()
        }
        .onAppear {
            consumeWidgetVoiceRequestIfNeeded()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            consumeWidgetVoiceRequestIfNeeded()
        }
        #endif
        .alert("Storage", isPresented: Binding(
            get: { app.persistenceMessage != nil },
            set: { if !$0 { app.persistenceMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.persistenceMessage ?? "")
        }
        .alert("Reminders", isPresented: Binding(
            get: { app.reminderMessage != nil },
            set: { if !$0 { app.reminderMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.reminderMessage ?? "")
        }
    }

    private func consumeWidgetVoiceRequestIfNeeded() {
        guard app.consumeWidgetVoiceRequest() else { return }
        selectedTab = .today
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AppNotifications.widgetVoicePlannerRequested, object: nil)
        }
    }
}
