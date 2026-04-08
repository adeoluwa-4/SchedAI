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
    @Namespace private var animation
    @State private var calendarToastMessage: String? = nil
    @State private var signInMessage: String? = nil
#if canImport(AuthenticationServices)
    @State private var appleSignIn = AppleIDSignInCoordinator()
#endif

    var body: some View {
        NavigationStack {
            ZStack {
                modernBackground
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // MARK: - Floating Header
                        floatingHeader
                            .padding(.top, 20)
                        
                        // MARK: - Profile Card
                        profileCard
                        
                        // MARK: - Settings Sections
                        VStack(spacing: 16) {
                            appearanceSection
                            planningSection
                            calendarSyncSection
                            remindersSection
                            aboutSection
                        }
                        
                        Color.clear.frame(height: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { app.refreshCalendarConnectionStatus() }
            .onChange(of: app.calendarSyncToast) { message in
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
        }
    }
    
    // MARK: - Modern Background
    
    private var modernBackground: some View {
        ZStack {
            if scheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.08),
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.96, green: 0.97, blue: 0.99),
                        Color.white
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            
            // Subtle mesh gradient overlay
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.blue.opacity(scheme == .dark ? 0.08 : 0.04),
                            Color.clear
                        ],
                        center: .topTrailing,
                        startRadius: 50,
                        endRadius: 400
                    )
                )
                .offset(x: 100, y: -200)
                .blur(radius: 80)
            
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.purple.opacity(scheme == .dark ? 0.06 : 0.03),
                            Color.clear
                        ],
                        center: .bottomLeading,
                        startRadius: 50,
                        endRadius: 400
                    )
                )
                .offset(x: -100, y: 300)
                .blur(radius: 80)
        }
        .ignoresSafeArea()
    }
    
    // MARK: - Floating Header
    
    private var floatingHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                Text("Personalize your experience")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Profile Card
    
    private var profileCard: some View {
        ModernCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "person.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(welcomeTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.primary)
                    
                    Text("Ready to plan your day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
#if canImport(AuthenticationServices)
                    if (app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        Button {
                            signInWithApple()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.badge.key")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("Sign in to personalize")
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(Color.blue.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
#endif
                }
                
                Spacer()
            }
            .padding(20)
        }
    }
    
    // MARK: - Appearance Section
    
    private var appearanceSection: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(icon: "paintbrush.pointed.fill", title: "Appearance", color: .pink)

                VStack(alignment: .leading, spacing: 12) {
                    SubsectionHeader("Theme")

                    VStack(spacing: 0) {
                        ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { index, theme in
                            ModernToggleButton(
                                icon: themeIcon(theme),
                                title: theme.title,
                                color: themeColor(theme),
                                isSelected: app.theme == theme
                            ) {
                                Haptics.light()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    app.theme = theme
                                }
                            }

                            if index < AppTheme.allCases.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Planning Section
    
    private var planningSection: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(icon: "calendar.badge.clock", title: "Planning", color: .indigo)

                VStack(alignment: .leading, spacing: 12) {
                    SubsectionHeader("Work Window")

                    NavigationLink {
                        WorkWindowPicker(start: $app.workStart, end: $app.workEnd)
                    } label: {
                        ModernRowView(
                            icon: "clock.fill",
                            title: "Work Window",
                            subtitle: workWindowText,
                            color: .indigo,
                            hasChevron: true
                        )
                    }
                    .buttonStyle(.plain)

                    SubsectionHeader("Actions")

                    ModernActionButton(
                        icon: "sparkles",
                        title: "Re-plan Today",
                        subtitle: "Rebuild today's schedule",
                        color: .blue
                    ) {
                        Haptics.medium()
                        app.planToday()
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Calendar Sync Section
    
    private var calendarSyncSection: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(icon: "calendar.badge.plus", title: "Calendar", color: .green)

                VStack(alignment: .leading, spacing: 12) {
                    SubsectionHeader("Sync")

                    ModernToggleRow(
                        icon: "calendar.badge.plus",
                        title: "Sync to Calendar",
                        isOn: calendarToggleBinding,
                        color: .green
                    )

                    SubsectionHeader("Status")

                    ModernRowView(
                        icon: "info.circle",
                        title: "Status",
                        subtitle: calendarStatusText,
                        color: .gray,
                        hasChevron: false
                    )

                    if shouldShowCalendarActions {
                        SubsectionHeader("Actions")
                        calendarDetailsSection
                    }
                }
            }
            .padding(20)
        }
    }
    
    @ViewBuilder
    private var calendarDetailsSection: some View {
        switch app.calendarConnectionStatus {
        case .notConnected:
            EmptyView()
            
        case .denied:
            VStack(spacing: 12) {
                ModernActionButton(
                    icon: "gearshape.fill",
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
                
                Text("Access denied — enable it in iOS Settings.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            
        case .connected:
            EmptyView()
            
        case .unavailable:
            EmptyView()
        }
    }
    
    // MARK: - Reminders Section
    
    private var remindersSection: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(icon: "bell.fill", title: "Reminders", color: .orange)

                VStack(alignment: .leading, spacing: 12) {
                    SubsectionHeader("Notifications")

                    ModernToggleRow(
                        icon: "bell.badge.fill",
                        title: "Enable Reminders",
                        isOn: $app.remindersEnabled,
                        color: .orange
                    )

                    if app.remindersEnabled {
                        SubsectionHeader("Timing")

                        NavigationLink {
                            ReminderLeadTimePicker(selected: $app.reminderLeadMinutes)
                        } label: {
                            ModernRowView(
                                icon: "timer",
                                title: "Lead Time",
                                subtitle: "\(app.reminderLeadMinutes) min before",
                                color: .orange,
                                hasChevron: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - About Section
    
    private var aboutSection: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(icon: "info.circle.fill", title: "About", color: .blue)

                VStack(alignment: .leading, spacing: 12) {
                    SubsectionHeader("Account")

#if canImport(AuthenticationServices)
                    ModernActionButton(
                        icon: "person.badge.key",
                        title: "Sign in with Apple",
                        subtitle: signInSubtitle,
                        color: .blue
                    ) {
                        signInWithApple()
                    }
#endif

                    SubsectionHeader("App")

                    ModernRowView(
                        icon: "app.badge",
                        title: "Version",
                        subtitle: versionString,
                        color: .gray,
                        hasChevron: false
                    )
                }
            }
            .padding(20)
        }
    }
    
    // MARK: - Helpers
    
    private var workWindowText: String {
        "\(app.workStart.formatted(date: .omitted, time: .shortened)) – \(app.workEnd.formatted(date: .omitted, time: .shortened))"
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
    
    private func themeIcon(_ theme: AppTheme) -> String {
        switch theme {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    
    private func themeColor(_ theme: AppTheme) -> Color {
        switch theme {
        case .system: return .blue
        case .light: return .orange
        case .dark: return .indigo
        }
    }

    private var welcomeTitle: String {
        if let name = app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "Welcome Back, \(name)"
        }
        return "Welcome Back"
    }

    private var shouldShowCalendarActions: Bool {
        switch app.calendarConnectionStatus {
        case .connected:
            return false
        case .denied:
            return true
        case .notConnected, .unavailable:
            return false
        }
    }

    private var signInSubtitle: String {
        if let name = app.userDisplayName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Signed in as \(name)"
        }
        return "Use your Apple ID name for greeting"
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
                        signInMessage = "Apple ID did not provide a name. If you previously signed in, Apple only shares the name once."
                    }
                } else {
                    signInMessage = "Apple ID did not provide a name. If you previously signed in, Apple only shares the name once."
                }
            case .failure:
                signInMessage = "Sign in was cancelled or failed."
            }
        }
    }
#endif
}

// MARK: - Modern Design Components

private struct ModernCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: 20, x: 0, y: 8)
    }
    
    private var cardBackground: some ShapeStyle {
        if scheme == .dark {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white,
                        Color.white.opacity(0.95)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
    
    private var borderColor: Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.04)
    }
    
    private var shadowColor: Color {
        scheme == .dark ? Color.black.opacity(0.4) : Color.black.opacity(0.05)
    }
}

private struct SectionHeader: View {
    let icon: String
    let title: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            Spacer()
        }
    }
}

private struct SubsectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
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

private struct ModernRowView: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let hasChevron: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 40, height: 40)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if hasChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct ModernActionButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            ModernRowView(
                icon: icon,
                title: title,
                subtitle: subtitle,
                color: color,
                hasChevron: true
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

private struct ModernToggleButton: View {
    let icon: String
    let title: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if isSelected {
                    ZStack {
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ModernToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    let color: Color
    
    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(color)
                }
                
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
            }
        }
        .tint(color)
        .padding(.vertical, 4)
    }
}
