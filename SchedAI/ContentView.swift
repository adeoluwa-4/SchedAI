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
