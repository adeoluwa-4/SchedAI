import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ContentView: View {
    @EnvironmentObject private var app: AppState
    @State private var selectedTab: Tab = .today

    private enum Tab: Hashable {
        case today
        case tasks
        case settings
    }

    var body: some View {
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
        .onAppear {
            consumeWidgetVoiceRequestIfNeeded()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            consumeWidgetVoiceRequestIfNeeded()
        }
        #endif
    }

    private func consumeWidgetVoiceRequestIfNeeded() {
        guard app.consumeWidgetVoiceRequest() else { return }
        selectedTab = .today
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: AppNotifications.widgetVoicePlannerRequested, object: nil)
        }
    }
}
