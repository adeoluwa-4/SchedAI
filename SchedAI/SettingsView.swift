import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    private enum SettingsDestination: String, CaseIterable, Identifiable {
        case account
        case appearance
        case workWindow
        case notifications
        case calendar
        case privacy
        case support

        var id: String { rawValue }

        var title: String {
            switch self {
            case .account: return "Account"
            case .appearance: return "Appearance"
            case .workWindow: return "Work Window"
            case .notifications: return "Notifications"
            case .calendar: return "Calendar"
            case .privacy: return "Privacy"
            case .support: return "Support"
            }
        }

        var icon: String {
            switch self {
            case .account: return "person.circle"
            case .appearance: return "paintbrush.pointed"
            case .workWindow: return "clock.badge.checkmark"
            case .notifications: return "bell"
            case .calendar: return "calendar.badge.plus"
            case .privacy: return "lock.shield"
            case .support: return "questionmark.bubble"
            }
        }

        var color: Color {
            switch self {
            case .account: return Color.brandBlue
            case .appearance: return .pink
            case .workWindow: return .indigo
            case .notifications: return .orange
            case .calendar: return .green
            case .privacy: return .teal
            case .support: return .gray
            }
        }

        var detailDescription: String {
            switch self {
            case .account:
                return "Manage the personal details SchedAI uses locally, including the optional Apple name shown in the app."
            case .appearance:
                return "Choose how SchedAI looks across the app. Theme changes stay on this device."
            case .workWindow:
                return "Control when SchedAI is allowed to place tasks and what happens to unfinished work."
            case .notifications:
                return "Set how reminders behave, when they arrive, and whether task names are shown in alerts."
            case .calendar:
                return "Connect SchedAI to your calendar so it can read busy time and write planned tasks when enabled."
            case .privacy:
                return "Review hosted AI Improve, voice, widget titles, calendar access, and what can leave the phone."
            case .support:
                return "Find version details, support links, legal pages, and product information."
            }
        }
    }

    private enum SettingsSheet: Identifiable {
        case accountDeletion
        case aiConsent

        var id: String {
            switch self {
            case .accountDeletion: return "accountDeletion"
            case .aiConsent: return "aiConsent"
            }
        }
    }

    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @State private var calendarToastMessage: String? = nil
    @State private var signInMessage: String? = nil
    @State private var presentedSheet: SettingsSheet? = nil
#if canImport(AuthenticationServices)
    @State private var appleSignIn = AppleIDSignInCoordinator()
#endif

    var body: some View {
        NavigationStack {
            ZStack {
                settingsBackground
                
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        floatingHeader
                            .padding(.top, 14)
                            .padding(.bottom, 12)

                        settingsGroups

                        appIdentity
                            .padding(.top, 30)
                            .padding(.bottom, 44)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { app.refreshCalendarConnectionStatus() }
            .onChange(of: app.calendarSyncToast) { _, message in
                guard let message else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    calendarToastMessage = message
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        calendarToastMessage = nil
                    }
                    app.calendarSyncToast = nil
                }
            }
            .alert("Calendar", isPresented: Binding(
                get: { app.calendarSyncMessage != nil },
                set: { if !$0 { app.calendarSyncMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(app.calendarSyncMessage ?? "")
            }
            .alert("Sign in", isPresented: Binding(
                get: { signInMessage != nil },
                set: { if !$0 { signInMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(signInMessage ?? "")
            }
            .overlay(alignment: .top) {
                if let message = calendarToastMessage {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                        .padding(.top, 10)
                        .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .accountDeletion:
                    AccountDeletionSheet {
                        app.deleteAccountAndLocalData()
                    }
                case .aiConsent:
                    AIConsentSheet {
                        app.hostedAIConsent = true
                    }
                }
            }
        }
    }
    
    // MARK: - Background
    
    private var settingsBackground: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color.black, Color(white: 0.05)]
                : [Color(red: 0.96, green: 0.97, blue: 0.98), Color.white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Header

    private var floatingHeader: some View {
        HStack {
            Text("Settings")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()
        }
    }
    
    // MARK: - Welcome Card
    
    private var profileCard: some View {
        SettingsPanel {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.brandBlue.opacity(scheme == .dark ? 0.16 : 0.12))
                        .frame(width: 56, height: 56)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.brandBlue)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(welcomeTitle)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text("Local by default. AI, calendar, widgets, voice, and reminders only use data when you enable them.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
#if canImport(AuthenticationServices)
                    if (app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        Button {
                            signInWithApple()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.badge.key")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Use Apple name locally")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(Color.brandBlue.opacity(scheme == .dark ? 0.16 : 0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.brandBlue)
                    }
#endif
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
    }

    // MARK: - App Identity

    private var appIdentity: some View {
        VStack(spacing: 12) {
            SettingsAppLogo(size: 76)

            Text("SchedAI")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(shortVersionString)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Groups

    private var settingsGroups: some View {
        VStack(spacing: 0) {
            SettingsPanel {
                VStack(spacing: 0) {
                    ForEach(SettingsDestination.allCases) { destination in
                        NavigationLink {
                            detailPage(for: destination)
                        } label: {
                            SettingsMenuRow(
                                icon: destination.icon,
                                title: destination.title,
                                subtitle: subtitle(for: destination),
                                color: destination.color
                            )
                        }
                        .buttonStyle(.plain)

                        if destination.id != SettingsDestination.allCases.last?.id {
                            SettingsDivider()
                                .padding(.trailing, 16)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder
    private func detailPage(for destination: SettingsDestination) -> some View {
        SettingsDetailPage(title: destination.title, background: settingsBackground) {
            SettingsIntroCard(
                icon: destination.icon,
                title: destination.title,
                description: destination.detailDescription,
                color: destination.color
            )

            switch destination {
            case .account:
                accountDetail
            case .appearance:
                appearanceDetail
            case .workWindow:
                workWindowDetail
            case .notifications:
                notificationsDetail
            case .calendar:
                calendarDetail
            case .privacy:
                privacyDetail
            case .support:
                supportDetail
            }
        }
    }

    private var accountDetail: some View {
        VStack(spacing: 22) {
            profileCard

            SettingsGroupCard(icon: "person.circle", title: "Profile", color: Color.brandBlue) {
                SettingsInfoRow(
                    icon: "person.text.rectangle",
                    title: "Profile",
                    subtitle: profileStatusText,
                    color: Color.brandBlue
                )

#if canImport(AuthenticationServices)
                if (app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    SettingsDivider()

                    SettingsActionRow(
                        icon: "person.badge.key",
                        title: "Use Apple Name Locally",
                        subtitle: "Optional local personalization only",
                        color: Color.brandBlue
                    ) {
                        signInWithApple()
                    }
                }
#endif
            }

            SettingsGroupCard(icon: "trash", title: "Account Deletion", color: .red) {
                SettingsInfoRow(
                    icon: "lock.shield",
                    title: "Delete Account and Data",
                    subtitle: "Remove your local profile and all SchedAI data from this device.",
                    color: .red
                )

                SettingsDivider()

                SettingsActionRow(
                    icon: "trash",
                    title: "Delete Account and Data",
                    subtitle: "Permanently deletes tasks, reminders, widget data, and local personalization.",
                    color: .red
                ) {
                    presentedSheet = .accountDeletion
                }
            }
        }
    }

    private var appearanceDetail: some View {
        SettingsGroupCard(icon: "paintbrush.pointed", title: "Appearance", color: .pink) {
            SettingsThemeRow(selected: $app.theme)
        }
    }

    private var workWindowDetail: some View {
        SettingsGroupCard(icon: "clock.badge.checkmark", title: "Work Window", color: .indigo) {
            SettingsInfoRow(
                icon: "calendar.day.timeline.leading",
                title: "Planning Boundary",
                subtitle: "When enabled, SchedAI keeps auto-scheduled tasks inside your preferred daily window.",
                color: .indigo
            )

            SettingsDivider()

            SettingsToggleRow(
                icon: "clock.badge.checkmark",
                title: "Use Work Window",
                subtitle: app.workWindowEnabled ? "Auto-schedule inside selected hours" : "Auto-schedule across daytime hours",
                isOn: $app.workWindowEnabled,
                color: .indigo
            )

            SettingsDivider()

            if app.workWindowEnabled {
                NavigationLink {
                    WorkWindowPicker(start: $app.workStart, end: $app.workEnd)
                } label: {
                    SettingsLinkRow(
                        icon: "clock",
                        title: "Work Window",
                        subtitle: workWindowText,
                        color: .indigo
                    )
                }
                .buttonStyle(.plain)
            } else {
                SettingsInfoRow(
                    icon: "clock",
                    title: "Work Window",
                    subtitle: workWindowText,
                    color: .indigo
                )
            }

            SettingsDivider()

            SettingsUnfinishedTaskRow(selected: $app.unfinishedTaskPolicy)
        }
    }

    private var notificationsDetail: some View {
        SettingsGroupCard(icon: "bell", title: "Notifications", color: .orange) {
            SettingsInfoRow(
                icon: "bell.and.waves.left.and.right",
                title: "Reminder Behavior",
                subtitle: "SchedAI schedules local alerts with the task, start time, and priority.",
                color: .orange
            )

            SettingsDivider()

            SettingsToggleRow(
                icon: "bell.badge",
                title: "Enable Reminders",
                subtitle: app.remindersEnabled ? "Task alerts are on" : "Task alerts are off",
                isOn: $app.remindersEnabled,
                color: .orange
            )

            if app.remindersEnabled {
                SettingsDivider()

                NavigationLink {
                    ReminderLeadTimePicker(selected: $app.reminderLeadMinutes)
                } label: {
                    SettingsLinkRow(
                        icon: "timer",
                        title: "Lead Time",
                        subtitle: "\(app.reminderLeadMinutes) min before",
                        color: .orange
                    )
                }
                .buttonStyle(.plain)

                SettingsDivider()

                SettingsInfoRow(
                    icon: "text.badge.checkmark",
                    title: "Alert Details",
                    subtitle: "Alerts show the task name, start time, and priority.",
                    color: .orange
                )
            }
        }
    }

    private var calendarDetail: some View {
        SettingsGroupCard(icon: "calendar.badge.plus", title: "Calendar", color: .green) {
            SettingsInfoRow(
                icon: "calendar",
                title: "Calendar Sync",
                subtitle: "SchedAI can read busy times and write planned tasks only after calendar permission is enabled.",
                color: .green
            )

            SettingsDivider()

            SettingsToggleRow(
                icon: "calendar.badge.plus",
                title: "Sync to Calendar",
                subtitle: calendarStatusText,
                isOn: calendarToggleBinding,
                color: .green
            )

            if app.calendarSyncEnabled {
                SettingsDivider()

                SettingsCalendarDestinationRow(
                    selected: $app.selectedCalendarDestinationID,
                    destinations: app.calendarDestinations
                )
            }

            SettingsDivider()

            SettingsInfoRow(
                icon: "info.circle",
                title: "Calendar Status",
                subtitle: app.calendarSyncEnabled ? "\(calendarStatusText) - reads busy times and writes planned tasks to \(calendarDestinationName)" : calendarStatusText,
                color: .gray
            )

            if app.calendarConnectionStatus == .denied {
                SettingsDivider()

                SettingsActionRow(
                    icon: "gearshape",
                    title: "Open iOS Settings",
                    subtitle: "Enable calendar permission",
                    color: .orange
                ) {
                    #if canImport(UIKit)
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                    #endif
                }
            }
        }
    }

    private var privacyDetail: some View {
        VStack(spacing: 22) {
            SettingsGroupCard(icon: "lock.shield", title: "Privacy", color: .teal) {
                SettingsInfoRow(
                    icon: "iphone.and.arrow.forward",
                    title: "Local First",
                    subtitle: "Offline parsing and Apple Intelligence run on device when available. Hosted AI is optional.",
                    color: .teal
                )

                SettingsDivider()

                SettingsToggleRow(
                    icon: "sparkles.rectangle.stack",
                    title: "Allow Hosted AI Improve",
                    subtitle: app.hostedAIConsent
                        ? "If Apple Intelligence is unavailable, task text may be sent to SchedAI and OpenAI when you tap Improve."
                        : "Off. Improve uses offline parsing and on-device Apple Intelligence when available.",
                    isOn: hostedAIBinding,
                    color: .teal
                )

                SettingsDivider()

                SettingsInfoRow(
                    icon: "mic",
                    title: "Voice Planning",
                    subtitle: "Apple speech and microphone access are used only when you start recording.",
                    color: .teal
                )

                SettingsDivider()

                SettingsInfoRow(
                    icon: "rectangle.inset.filled",
                    title: "Widget Titles",
                    subtitle: "Control whether SchedAI widgets show real task names or private placeholders.",
                    color: .teal
                )

                SettingsDivider()

                SettingsToggleRow(
                    icon: app.showTaskTitlesInWidget ? "eye" : "eye.slash",
                    title: "Always Show Titles in Widgets",
                    subtitle: app.showTaskTitlesInWidget
                        ? "Widgets show task names on the Home Screen and Lock Screen"
                        : "Widgets hide task names behind private placeholders",
                    isOn: $app.showTaskTitlesInWidget,
                    color: .teal
                )

                SettingsDivider()

                SettingsActionRow(
                    icon: "slider.horizontal.3",
                    title: "Privacy Choices",
                    subtitle: "Review AI, calendar, voice, and reminder choices",
                    color: .teal
                ) {
                    openURL(LegalLinks.privacyChoices)
                }

                SettingsDivider()

                SettingsActionRow(
                    icon: "hand.raised",
                    title: "Privacy Policy",
                    subtitle: "See what data stays local and what can leave the device",
                    color: .teal
                ) {
                    openURL(LegalLinks.privacy)
                }
            }
        }
    }

    private var supportDetail: some View {
        SettingsGroupCard(icon: "questionmark.bubble", title: "Support", color: .gray) {
            SettingsInfoRow(
                icon: "app.badge",
                title: "Version",
                subtitle: versionString,
                color: .gray
            )

            SettingsDivider()

            SettingsActionRow(
                icon: "questionmark.bubble",
                title: "Support",
                subtitle: "Contact support or review common setup answers",
                color: .gray
            ) {
                openURL(LegalLinks.support)
            }

            SettingsDivider()

            SettingsActionRow(
                icon: "doc.text",
                title: "Terms",
                subtitle: "Read the product terms",
                color: .gray
            ) {
                openURL(LegalLinks.terms)
            }
        }
    }

    private func subtitle(for destination: SettingsDestination) -> String {
        switch destination {
        case .account:
            return profileStatusText
        case .appearance:
            return app.theme.title
        case .workWindow:
            return app.workWindowEnabled ? workWindowText : "Off - daytime scheduling"
        case .notifications:
            return app.remindersEnabled ? "Reminders on - \(app.reminderLeadMinutes) min before" : "Reminders off"
        case .calendar:
            return app.calendarSyncEnabled ? "\(calendarStatusText) - \(calendarDestinationName)" : calendarStatusText
        case .privacy:
            return app.hostedAIConsent ? "Hosted AI Improve allowed" : "Hosted AI Improve off"
        case .support:
            return "\(shortVersionString), legal, and help"
        }
    }

    // MARK: - Helpers
    
    private var workWindowText: String {
        guard app.workWindowEnabled else { return "Off - daytime scheduling" }
        return "\(app.workStart.formatted(date: .omitted, time: .shortened)) – \(app.workEnd.formatted(date: .omitted, time: .shortened))"
    }
    
    private var calendarToggleBinding: Binding<Bool> {
        Binding(
            get: { app.calendarSyncEnabled },
            set: { newValue in
                if !newValue {
                    app.calendarSyncEnabled = false
                    app.refreshCalendarConnectionStatus()
                    return
                }

                app.enableCalendarSyncUserDriven()
            }
        )
    }
    
    private var calendarStatusText: String {
        switch app.calendarConnectionStatus {
        case .notConnected: return "Not connected"
        case .connected: return "Connected"
        case .denied: return "Denied"
        case .unavailable: return "Unavailable"
        }
    }

    private var calendarDestinationName: String {
        app.calendarDestinations.first(where: { $0.id == app.selectedCalendarDestinationID })?.title ?? "your calendar"
    }
    
    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var shortVersionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(short)"
    }

    private var profileStatusText: String {
        if let name = app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "Using Apple-provided name: \(name)"
        }
        return "Optional local-only personalization"
    }
    
    private var welcomeTitle: String {
        if let name = app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "Welcome Back, \(name)"
        }
        return "Welcome Back"
    }

    private var hostedAIBinding: Binding<Bool> {
        Binding(
            get: { app.hostedAIConsent },
            set: { newValue in
                if newValue {
                    if app.hostedAIConsent {
                        return
                    }
                    presentedSheet = .aiConsent
                } else {
                    app.hostedAIConsent = false
                }
            }
        )
    }

#if canImport(AuthenticationServices)
    private func signInWithApple() {
        appleSignIn.start { result in
            switch result {
            case .success(let credential):
                if let fullName = credential.fullName {
                    let formatter = PersonNameComponentsFormatter()
                    let name = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        app.userDisplayName = name
                    } else {
                        signInMessage = "Apple only shares the name once. SchedAI uses it only for local personalization on this device."
                    }
                } else {
                    signInMessage = "Apple only shares the name once. SchedAI uses it only for local personalization on this device."
                }
            case .failure:
                signInMessage = "Apple name sharing was cancelled or failed."
            }
        }
    }
#endif
}

// MARK: - Modern Design Components

private struct SettingsPanel<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(scheme == .dark ? 0.16 : 0.22), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.22 : 0.08), radius: 20, x: 0, y: 8)
    }
}

private struct SettingsAppLogo: View {
    let size: CGFloat

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let uiImage = UIImage(named: "LauchLogo") {
                Image(uiImage: uiImage)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                fallbackLogo
            }
            #else
            fallbackLogo
            #endif
        }
        .frame(width: size, height: size)
        .shadow(color: Color.brandBlue.opacity(0.16), radius: 14, x: 0, y: 8)
    }

    private var fallbackLogo: some View {
        Image(systemName: "calendar")
            .font(.system(size: size * 0.58, weight: .semibold))
            .foregroundStyle(Color.brandBlue)
            .frame(width: size, height: size)
            .background(Color.brandBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SettingsGroupCard<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    let content: Content

    init(icon: String, title: String, color: Color, @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.color = color
        self.content = content()
    }

    var body: some View {
        SettingsPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SettingsSectionIcon(systemName: icon, color: color)

                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)

                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }
}

private struct SettingsIntroCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    var body: some View {
        SettingsPanel {
            HStack(alignment: .top, spacing: 14) {
                SettingsIcon(systemName: icon, color: color)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(description)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
    }
}

private struct SettingsDetailPage<Background: View, Content: View>: View {
    let title: String
    let background: Background
    let content: Content

    init(title: String, background: Background, @ViewBuilder content: () -> Content) {
        self.title = title
        self.background = background
        self.content = content()
    }

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 54)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

private struct AccountDeletionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var didDelete = false

    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 42, height: 5)
                .padding(.top, 10)

            SettingsIcon(
                systemName: didDelete ? "checkmark.circle.fill" : "trash",
                color: didDelete ? .green : .red,
                size: 68
            )

            VStack(spacing: 10) {
                Text(didDelete ? "Account Deleted" : "Delete Account and Data?")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)

                Text(didDelete ? deletedMessage : confirmationMessage)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if didDelete {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
            } else {
                VStack(spacing: 10) {
                    Button(role: .destructive) {
                        onDelete()
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            didDelete = true
                        }
                    } label: {
                        Text("Delete Account and Data")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    Button {
                        dismiss()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .presentationDetents([.height(didDelete ? 360 : 430), .medium])
        .presentationDragIndicator(.hidden)
        .background(scheme == .dark ? Color.black : Color(.systemBackground))
    }

    private var confirmationMessage: String {
        "This permanently deletes your local profile, tasks, reminders, widget data, and SchedAI calendar events from this device."
    }

    private var deletedMessage: String {
        "Your SchedAI account and local data have been deleted from this device."
    }
}

private struct SettingsMenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SettingsIcon(systemName: icon, color: color, size: 50)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 20)
        .contentShape(Rectangle())
    }
}

private struct SettingsSectionIcon: View {
    let systemName: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.14))
                .frame(width: 28, height: 28)

            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

private struct SettingsIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
                .frame(width: size, height: size)

            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

private struct SettingsDivider: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Rectangle()
            .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

private struct SettingsInfoRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            SettingsIcon(systemName: icon, color: color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct SettingsLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(spacing: 11) {
            SettingsIcon(systemName: icon, color: color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

private struct SettingsActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsLinkRow(icon: icon, title: title, subtitle: subtitle, color: color)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let color: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 11) {
                SettingsIcon(systemName: icon, color: color)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .tint(color)
        .padding(.vertical, 12)
    }
}

private struct SettingsThemeRow: View {
    @Binding var selected: AppTheme

    var body: some View {
        HStack(spacing: 11) {
            SettingsIcon(systemName: "paintbrush.pointed", color: .pink)

            VStack(alignment: .leading, spacing: 4) {
                Text("Theme")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(selected.title)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Picker("Theme", selection: $selected) {
                ForEach(AppTheme.allCases) { theme in
                    Text(theme.title).tag(theme)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .tint(Color.brandBlue)
        }
        .padding(.vertical, 12)
        .onChange(of: selected) { _, _ in
            Haptics.light()
        }
    }
}

private struct SettingsUnfinishedTaskRow: View {
    @Binding var selected: UnfinishedTaskPolicy

    var body: some View {
        HStack(spacing: 11) {
            SettingsIcon(systemName: "checklist.unchecked", color: .yellow)

            VStack(alignment: .leading, spacing: 4) {
                Text("Unfinished Tasks")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(selected.subtitle)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Picker("Unfinished Tasks", selection: $selected) {
                ForEach(UnfinishedTaskPolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .tint(Color.brandBlue)
        }
        .padding(.vertical, 12)
        .onChange(of: selected) { _, _ in
            Haptics.light()
        }
    }
}

private struct SettingsCalendarDestinationRow: View {
    @Binding var selected: String
    let destinations: [CalendarManager.CalendarDestination]

    var body: some View {
        HStack(spacing: 11) {
            SettingsIcon(systemName: "calendar.badge.checkmark", color: .green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar Destination")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(selectedDestination?.subtitle ?? "Choose where SchedAI writes planned tasks")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Picker("Calendar Destination", selection: $selected) {
                ForEach(destinations) { destination in
                    Text(destination.title).tag(destination.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .tint(Color.brandBlue)
        }
        .padding(.vertical, 12)
        .onChange(of: selected) { _, _ in
            Haptics.light()
        }
    }

    private var selectedDestination: CalendarManager.CalendarDestination? {
        destinations.first { $0.id == selected }
    }
}

#if canImport(AuthenticationServices)
private final class AppleIDSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var completion: ((Result<ASAuthorizationAppleIDCredential, Error>) -> Void)?
    private var controller: ASAuthorizationController?

    func start(completion: @escaping (Result<ASAuthorizationAppleIDCredential, Error>) -> Void) {
        self.completion = completion
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            completion?(.success(credential))
        }
        self.controller = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion?(.failure(error))
        self.controller = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = activeScene?.windows.first { $0.isKeyWindow } ?? activeScene?.windows.first
        return window ?? UIWindow()
        #else
        return ASPresentationAnchor()
        #endif
    }
}
#endif
