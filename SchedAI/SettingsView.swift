import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @State private var calendarToastMessage: String? = nil
    @State private var signInMessage: String? = nil
    @State private var showAIConsentSheet: Bool = false
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
                            .padding(.top, 26)
                            .padding(.bottom, 54)

                        appIdentity
                            .padding(.bottom, 34)

                        settingsGroups

                        Color.clear.frame(height: 40)
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
            .sheet(isPresented: $showAIConsentSheet) {
                AIConsentSheet {
                    app.hostedAIConsent = true
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
                    
                    Text("Everything here stays local unless you choose hosted AI improve.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    
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
        VStack(spacing: 16) {
            profileCard
            accountGroup
            notificationsGroup
            privacyGroup
            aboutGroup
        }
    }

    private var accountGroup: some View {
        SettingsGroupCard(icon: "person.circle", title: "Account", color: Color.brandBlue) {
            SettingsInfoRow(
                icon: "person.text.rectangle",
                title: "Profile",
                subtitle: profileStatusText,
                color: Color.brandBlue
            )

            SettingsDivider()

            SettingsThemeRow(selected: $app.theme)

            SettingsDivider()

            SettingsToggleRow(
                icon: "clock.badge.checkmark",
                title: "Use Work Window",
                subtitle: app.workWindowEnabled ? "Auto-schedule inside selected hours" : "Auto-schedule across the full day",
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
        }
    }

    private var notificationsGroup: some View {
        SettingsGroupCard(icon: "bell", title: "Notifications", color: .orange) {
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
            }

            SettingsDivider()

            SettingsUnfinishedTaskRow(selected: $app.unfinishedTaskPolicy)

            SettingsDivider()

            SettingsToggleRow(
                icon: "calendar.badge.plus",
                title: "Sync to Calendar",
                subtitle: calendarStatusText,
                isOn: calendarToggleBinding,
                color: .green
            )

            SettingsDivider()

            SettingsInfoRow(
                icon: "info.circle",
                title: "Calendar Status",
                subtitle: app.calendarSyncEnabled ? "\(calendarStatusText) - reads busy times and writes SchedAI events" : calendarStatusText,
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

    private var aboutGroup: some View {
        SettingsGroupCard(icon: "info.circle", title: "About", color: .gray) {
            SettingsInfoRow(
                icon: "app.badge",
                title: "Version",
                subtitle: versionString,
                color: .gray
            )

            SettingsDivider()

            SettingsInfoRow(
                icon: "person.badge.key",
                title: "Apple Name",
                subtitle: "Optional local personalization only",
                color: .gray
            )
        }
    }

    private var privacyGroup: some View {
        SettingsGroupCard(icon: "lock.shield", title: "Privacy & Support", color: .teal) {
            SettingsToggleRow(
                icon: "sparkles.rectangle.stack",
                title: "Allow Hosted AI Improve",
                subtitle: app.hostedAIConsent
                    ? "Task text may be sent to SchedAI and OpenAI when you tap Improve."
                    : "Off. Preview stays on device until you choose otherwise.",
                isOn: hostedAIBinding,
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

            SettingsDivider()

            SettingsActionRow(
                icon: "doc.text",
                title: "Terms",
                subtitle: "Read the product terms",
                color: .teal
            ) {
                openURL(LegalLinks.terms)
            }

            SettingsDivider()

            SettingsActionRow(
                icon: "questionmark.bubble",
                title: "Support",
                subtitle: "Contact support or review common setup answers",
                color: .teal
            ) {
                openURL(LegalLinks.support)
            }
        }
    }

    // MARK: - Helpers
    
    private var workWindowText: String {
        guard app.workWindowEnabled else { return "Off - full-day scheduling" }
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
                    showAIConsentSheet = true
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SettingsSectionIcon(systemName: icon, color: color)

                    Text(title)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                VStack(spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
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

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.16))
                .frame(width: 42, height: 42)

            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
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
