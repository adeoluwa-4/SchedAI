import SwiftUI
#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(UIKit)
import UIKit
#endif

struct LogoLaunchView: View {
    private enum Phase { case logo, onboarding, splash, notifications, main }

    @EnvironmentObject private var app: AppState
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hasSeenNotificationOnboarding") private var hasSeenNotificationOnboarding = false
    @State private var phase: Phase = .logo
    private let logoHoldSeconds: TimeInterval = 1.2

    var body: some View {
        ZStack {
            switch phase {
            case .logo:
                LaunchLogoScreen()
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + logoHoldSeconds) {
                            withAnimation(.easeOut(duration: 0.25)) {
                                phase = hasCompletedOnboarding ? .splash : .onboarding
                            }
                        }
                    }

            case .onboarding:
                OnboardingView(onFinish: {
                    hasCompletedOnboarding = true
                    withAnimation(.easeOut(duration: 0.25)) {
                        phase = .splash
                    }
                })
                .transition(.opacity)

            case .splash:
                SplashView(onStart: {
                    startMainExperience()
                })
                .transition(.opacity)

            case .notifications:
                NotificationPermissionOnboardingView(
                    onEnable: completeNotificationOnboarding,
                    onSkip: completeNotificationOnboarding
                )
                .transition(.opacity)

            case .main:
                ContentView() // Home (Today first tab)
                    .transition(.opacity)
            }
        }
    }

    private func completeNotificationOnboarding() {
        hasSeenNotificationOnboarding = true
        showMain()
    }

    private func showMain() {
        withAnimation(.easeOut(duration: 0.25)) {
            phase = .main
        }
    }

    private func startMainExperience() {
        guard !hasSeenNotificationOnboarding else {
            showMain()
            return
        }

        NotificationManager.authorizationStatus { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .denied:
                    hasSeenNotificationOnboarding = true
                    showMain()
                case .notDetermined:
                    withAnimation(.easeOut(duration: 0.25)) {
                        phase = .notifications
                    }
                }
            }
        }
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var app: AppState
    @AppStorage("hasSeenWidgetGuide") private var hasSeenWidgetGuide = false
    @State private var page = 0
    @State private var hasCompletedAppleSignIn = false
    @State private var hasCompletedCalendarChoice = false
    @State private var needsNameEntry = false
    @State private var firstNameInput = ""
    @State private var isRequestingCalendar = false
    @State private var signInMessage: String? = nil
    @State private var presentedSheet: OnboardingSheet? = nil

    let onFinish: () -> Void

    private let pages = OnboardingPage.pages

    var body: some View {
        OnboardingBackground {
            VStack(spacing: 0) {
                if needsNameEntry {
                    NameEntryOnboardingScreen(firstName: $firstNameInput)
                } else if hasCompletedAppleSignIn && !hasCompletedCalendarChoice {
                    CalendarConnectOnboardingScreen(
                        status: app.calendarConnectionStatus,
                        isRequesting: isRequestingCalendar
                    )
                } else if hasCompletedAppleSignIn {
                    TabView(selection: $page) {
                        ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                            OnboardingPageView(page: page)
                                .tag(index)
                                .padding(.horizontal, 24)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

                    pageDots
                        .padding(.bottom, 18)
                } else {
                    SignInOnboardingScreen()
                }

                bottomControls
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
            }
        }
        .alert("Sign in optional", isPresented: Binding(
            get: { signInMessage != nil },
            set: { if !$0 { signInMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInMessage ?? "")
        }
        .alert("Calendar", isPresented: Binding(
            get: { app.calendarSyncMessage != nil },
            set: { if !$0 { app.calendarSyncMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.calendarSyncMessage ?? "")
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .widgetGuide:
                WidgetGuideSheet(
                    onDone: completeWidgetGuide,
                    onMaybeLater: completeWidgetGuide
                )
            }
        }
        .onAppear {
            app.refreshCalendarConnectionStatus()
        }
        .onChange(of: app.calendarConnectionStatus) { _, status in
            guard isRequestingCalendar else { return }
            switch status {
            case .connected:
                isRequestingCalendar = false
                completeCalendarOnboarding()
            case .denied, .unavailable:
                isRequestingCalendar = false
            case .notConnected:
                break
            }
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(pages.indices, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.brandBlue : Color.secondary.opacity(0.28))
                    .frame(width: index == page ? 22 : 8, height: 8)
                    .animation(.spring(response: 0.28, dampingFraction: 0.85), value: page)
            }
        }
    }

    private var bottomControls: some View {
        HStack(spacing: 12) {
            if hasCompletedAppleSignIn && !needsNameEntry && page > 0 {
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                        page -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 52, height: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.brandBlue)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.brandBlue.opacity(0.16), lineWidth: 1)
                        )
                )
            }

            if needsNameEntry {
                VStack(spacing: 10) {
                    Button {
                        saveManualFirstName()
                    } label: {
                        HStack(spacing: 10) {
                            Text("Continue")
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandBlue)
                    .disabled(firstNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        skipManualName()
                    } label: {
                        Text("Skip")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            } else if hasCompletedAppleSignIn && !hasCompletedCalendarChoice {
                VStack(spacing: 10) {
                    Button {
                        connectCalendarFromOnboarding()
                    } label: {
                        HStack(spacing: 10) {
                            if isRequestingCalendar {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "calendar.badge.plus")
                            }
                            Text(isRequestingCalendar ? "Connecting..." : calendarButtonTitle)
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandBlue)
                    .disabled(isRequestingCalendar)

                    Button {
                        skipCalendarOnboarding()
                    } label: {
                        Text(app.calendarConnectionStatus == .connected ? "Continue" : "Not Now")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(isRequestingCalendar)
                }
            } else if hasCompletedAppleSignIn {
                Button {
                    if page == pages.count - 1 {
                        if hasSeenWidgetGuide {
                            onFinish()
                        } else {
                            presentedSheet = .widgetGuide
                        }
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            page += 1
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(primaryButtonTitle)
                        Image(systemName: primaryButtonIcon)
                    }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
            } else {
                VStack(spacing: 10) {
                    #if canImport(AuthenticationServices)
                    AppleSignInControl(onCompletion: handleAppleSignInResult)
                    #else
                    Button {
                        continueWithoutApple()
                    } label: {
                        Text("Continue without Apple")
                            .font(.headline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandBlue)
                    #endif

                    #if canImport(AuthenticationServices)
                    Button {
                        continueWithoutApple()
                    } label: {
                        Text("Continue without Apple")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    #endif
                }
                .frame(maxWidth: .infinity)
                #if !canImport(AuthenticationServices)
                .onAppear {
                    signInMessage = "Sign in with Apple is unavailable on this device. You can continue without it."
                }
                #endif
            }
        }
    }

    private var primaryButtonTitle: String {
        guard page == pages.count - 1 else { return "Continue" }
        return hasSeenWidgetGuide ? "Start Planning" : "How to Add the Widget"
    }

    private var primaryButtonIcon: String {
        guard page == pages.count - 1 else { return "arrow.right" }
        return hasSeenWidgetGuide ? "checkmark" : "questionmark.circle"
    }

    private var calendarButtonTitle: String {
        app.calendarConnectionStatus == .connected ? "Calendar Connected" : "Connect Calendar"
    }

    #if canImport(AuthenticationServices)
    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                signInMessage = "Apple sign-in did not return a valid credential. Try again."
                return
            }

            if let fullName = credential.fullName {
                let formatter = PersonNameComponentsFormatter()
                let name = formatter.string(from: fullName).trimmingCharacters(in: .whitespacesAndNewlines)
                app.userDisplayName = cleanDisplayName(from: fullName.givenName) ?? cleanDisplayName(from: name) ?? app.userDisplayName
            }

            if app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
               let fallbackName = displayNameFromEmail(credential.email) {
                app.userDisplayName = fallbackName
            }

            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                if app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                    needsNameEntry = true
                } else {
                    continueAfterAppleSignIn()
                }
            }
        case .failure:
            signInMessage = "Sign in with Apple was cancelled or failed. You can try again or continue without it."
        }
    }
    #else
    private func handleAppleSignInResult(_ result: Result<Void, Error>) {
        signInMessage = "Sign in with Apple is unavailable on this device. You can continue without it."
    }
    #endif

    private func continueWithoutApple() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            firstNameInput = ""
            needsNameEntry = false
            continueAfterAppleSignIn()
        }
    }

    private func saveManualFirstName() {
        let name = firstNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        app.userDisplayName = name
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            needsNameEntry = false
            continueAfterAppleSignIn()
        }
    }

    private func skipManualName() {
        firstNameInput = ""
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            needsNameEntry = false
            continueAfterAppleSignIn()
        }
    }

    private func continueAfterAppleSignIn() {
        hasCompletedAppleSignIn = true
        hasCompletedCalendarChoice = app.calendarConnectionStatus == .connected
        page = 0
    }

    private func connectCalendarFromOnboarding() {
        if app.calendarConnectionStatus == .connected {
            completeCalendarOnboarding()
            return
        }

        isRequestingCalendar = true
        app.enableCalendarSyncUserDriven()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if app.calendarConnectionStatus == .connected {
                isRequestingCalendar = false
                completeCalendarOnboarding()
            } else if app.calendarConnectionStatus != .notConnected {
                isRequestingCalendar = false
            }
        }
    }

    private func skipCalendarOnboarding() {
        isRequestingCalendar = false
        completeCalendarOnboarding()
    }

    private func completeCalendarOnboarding() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            hasCompletedCalendarChoice = true
            page = 0
        }
    }

    private func completeWidgetGuide() {
        hasSeenWidgetGuide = true
        presentedSheet = nil
        onFinish()
    }

    private func cleanDisplayName(from rawValue: String?) -> String? {
        let cleaned = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .first
            .map(String.init)
        return cleaned?.isEmpty == false ? cleaned : nil
    }

    private func displayNameFromEmail(_ email: String?) -> String? {
        guard let localPart = email?.split(separator: "@").first else { return nil }
        let candidate = localPart
            .split(whereSeparator: { ".-_+".contains($0) })
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let candidate, !candidate.isEmpty, candidate.rangeOfCharacter(from: .letters) != nil else {
            return nil
        }

        return candidate.prefix(1).uppercased() + candidate.dropFirst()
    }
}

private enum OnboardingSheet: Identifiable {
    case widgetGuide

    var id: String {
        switch self {
        case .widgetGuide:
            return "widgetGuide"
        }
    }
}

private struct NotificationPermissionOnboardingView: View {
    @EnvironmentObject private var app: AppState
    @State private var isCheckingPermission = true
    @State private var isRequestingPermission = false
    @State private var message: String? = nil

    let onEnable: () -> Void
    let onSkip: () -> Void

    var body: some View {
        NotificationOnboardingBackground {
            VStack(spacing: 0) {
                Spacer(minLength: 96)

                VStack(spacing: 28) {
                    OnboardingLogoImage(width: 72, height: 72)

                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 86, height: 86)

                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(Color.brandBlue)
                    }

                    VStack(spacing: 12) {
                        Text("Stay ahead of your plan.")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.88)

                        Text("SchedAI can remind you before scheduled tasks so your day stays on track.")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 320)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "slider.horizontal.3")
                        Text("You can change this anytime in Settings.")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.brandBlue)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    Button {
                        requestNotifications()
                    } label: {
                        HStack(spacing: 10) {
                            if isRequestingPermission {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "bell.fill")
                            }
                            Text(isRequestingPermission ? "Requesting..." : "Enable Notifications")
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                    }
                    .buttonStyle(.plain)
                    .background(Color.white)
                    .foregroundStyle(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .disabled(isCheckingPermission || isRequestingPermission)

                    Button("Not Now") {
                        onSkip()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .disabled(isRequestingPermission)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .alert("Notifications", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {
                onSkip()
            }
        } message: {
            Text(message ?? "")
        }
        .onAppear(perform: refreshPermissionState)
    }

    private func refreshPermissionState() {
        NotificationManager.authorizationStatus { status in
            DispatchQueue.main.async {
                isCheckingPermission = false
                switch status {
                case .authorized:
                    app.remindersEnabled = true
                    onEnable()
                case .denied:
                    onSkip()
                case .notDetermined:
                    break
                }
            }
        }
    }

    private func requestNotifications() {
        isRequestingPermission = true
        NotificationManager.requestPermission { granted in
            DispatchQueue.main.async {
                isRequestingPermission = false
                if granted {
                    app.remindersEnabled = true
                    onEnable()
                } else {
                    message = "Notifications were not enabled. You can turn them on later in Settings."
                }
            }
        }
    }
}

private struct NameEntryOnboardingScreen: View {
    @Binding var firstName: String
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 92)

            VStack(spacing: 16) {
                OnboardingLogoImage(width: 78, height: 78)

                VStack(spacing: 10) {
                    Text("What should we call you?")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.84)

                    Text("This keeps the start page personal. Your name stays on this device.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 310)
                }
            }

            TextField("First name", text: $firstName)
                .textContentType(.givenName)
                .submitLabel(.continue)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .frame(height: 62)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(isFocused ? 0.28 : 0.12), lineWidth: 1)
                        )
                )
                .focused($isFocused)
                .padding(.horizontal, 24)

            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                Text("Used only for your welcome message.")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.brandBlue)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
            )

            Spacer(minLength: 20)
        }
        .onAppear {
            isFocused = true
        }
    }
}

private struct OnboardingLogoImage: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let uiImage = UIImage(named: "LauchLogo") {
                Image(uiImage: uiImage)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
            #else
            fallback
            #endif
        }
        .frame(width: width, height: height)
    }

    private var fallback: some View {
        Image(systemName: "calendar.badge.clock")
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: min(width, height) * 0.78, weight: .semibold))
            .foregroundStyle(Color.brandBlue)
    }
}

private struct NotificationOnboardingBackground<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            (scheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            content()
        }
    }
}

private struct OnboardingPage {
    let icon: String
    let eyebrow: String
    let title: String
    let subtitle: String
    let visual: OnboardingVisual

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "wand.and.stars",
            eyebrow: "Plan clearly",
            title: "Type or speak naturally.",
            subtitle: "Add tasks in your own words, then preview the plan before anything changes.",
            visual: .plan
        ),
        OnboardingPage(
            icon: "square.grid.2x2",
            eyebrow: "Add the widget",
            title: "See today at a glance.",
            subtitle: "Instantly see what is happening now, what is next, and your progress.",
            visual: .widget
        )
    ]
}

private enum OnboardingVisual {
    case plan
    case widget
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 22)

            OnboardingHeroCard(page: page)

            VStack(spacing: 9) {
                Text(page.eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)

                Text(page.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(page.subtitle)
                    .font(.subheadline.weight(.medium))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
    }
}

private struct WidgetGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let onDone: () -> Void
    let onMaybeLater: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 42, height: 5)
                .padding(.top, 10)

            VStack(spacing: 14) {
                WidgetMiniPreview()
                    .frame(height: 120)

                VStack(spacing: 8) {
                    Text("How to add the widget")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)

                    Text("iOS requires you to add widgets from the Home Screen. This takes a few seconds.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                }
            }

            VStack(spacing: 10) {
                WidgetGuideStep(number: "1", icon: "hand.tap", title: "Touch and hold the Home Screen", detail: "Wait until the icons start to move.")
                WidgetGuideStep(number: "2", icon: "plus", title: "Tap +", detail: "Open the widget picker from the top corner.")
                WidgetGuideStep(number: "3", icon: "magnifyingglass", title: "Search SchedAI", detail: "Choose a widget size, then tap Add Widget.")
            }

            VStack(spacing: 10) {
                Button {
                    dismiss()
                    onDone()
                } label: {
                    Text("Done")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)

                Button {
                    dismiss()
                    onMaybeLater()
                } label: {
                    Text("Maybe later")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
        .presentationDetents([.height(620), .large])
        .presentationDragIndicator(.hidden)
        .background(scheme == .dark ? Color.black : Color(.systemBackground))
    }
}

private struct WidgetGuideStep: View {
    let number: String
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.brandBlue.opacity(0.13))

                Image(systemName: icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(number)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.brandBlue))

                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.secondary.opacity(0.09))
        )
    }
}

private struct WidgetMiniPreview: View {
    var body: some View {
        HStack(spacing: 0) {
            WidgetMiniColumn(title: "NOW", value: "Workout", detail: "45m", color: Color.brandBlue, icon: "dumbbell")
            Divider().overlay(Color.white.opacity(0.16))
            WidgetMiniColumn(title: "PROGRESS", value: "40%", detail: "2 of 5 tasks", color: .green, icon: "circle.dashed")
            Divider().overlay(Color.white.opacity(0.16))
            WidgetMiniColumn(title: "NEXT", value: "1:00 PM", detail: "Meeting", color: .purple, icon: "calendar")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct WidgetMiniColumn: View {
    let title: String
    let value: String
    let detail: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
            Text(detail)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
    }
}

private struct OnboardingBackground<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color.black, Color(red: 0.02, green: 0.04, blue: 0.08)]
                    : [Color(red: 0.96, green: 0.98, blue: 1.0), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color.brandBlue.opacity(scheme == .dark ? 0.18 : 0.08), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .ignoresSafeArea()

            content()
        }
    }
}

private struct SignInOnboardingScreen: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 56)

            VStack(spacing: 28) {
                LaunchLogoImage()
                    .frame(width: 72, height: 72)
                    .shadow(color: Color.brandBlue.opacity(0.22), radius: 18, x: 0, y: 10)

                VStack(spacing: 14) {
                    Text("Plan your day faster.")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Text("Use Apple to fill your name, enter one yourself, or skip personalization.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 310)
                }

                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                    Text("Your name stays local on this device.")
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.brandBlue.opacity(scheme == .dark ? 0.18 : 0.1))
                )
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 32)
        }
    }
}

private struct CalendarConnectOnboardingScreen: View {
    @Environment(\.colorScheme) private var scheme
    let status: CalendarManager.ConnectionStatus
    let isRequesting: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            VStack(spacing: 24) {
                ZStack {
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .fill(Color.brandBlue.opacity(scheme == .dark ? 0.16 : 0.1))
                        .frame(width: 106, height: 106)

                    Image(systemName: status == .connected ? "calendar.badge.checkmark" : "calendar.badge.plus")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(Color.brandBlue)
                }

                VStack(spacing: 12) {
                    Text(status == .connected ? "Calendar is connected." : "Connect your calendar.")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.82)

                    Text("SchedAI can read busy time and write planned tasks only after you allow calendar access.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 330)
                }

                VStack(spacing: 10) {
                    CalendarBenefitPill(icon: "eye", text: "Avoid scheduling over busy blocks")
                    CalendarBenefitPill(icon: "square.and.pencil", text: "Add your plan to the calendar you choose")
                    CalendarBenefitPill(icon: "slider.horizontal.3", text: "Optional and adjustable in Settings")
                }
                .frame(maxWidth: 340)

                HStack(spacing: 10) {
                    Image(systemName: statusIcon)
                    Text(statusText)
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.brandBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.brandBlue.opacity(scheme == .dark ? 0.18 : 0.1))
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)

            Spacer(minLength: 24)
        }
    }

    private var statusIcon: String {
        if isRequesting { return "arrow.triangle.2.circlepath" }
        switch status {
        case .connected: return "checkmark.shield"
        case .denied: return "exclamationmark.triangle"
        case .unavailable: return "xmark.octagon"
        case .notConnected: return "lock.shield"
        }
    }

    private var statusText: String {
        if isRequesting { return "Waiting for Calendar permission..." }
        switch status {
        case .connected: return "Connected. You can continue."
        case .denied: return "Permission is denied in iOS Settings."
        case .unavailable: return "Calendar is unavailable on this device."
        case .notConnected: return "You can skip this and connect later."
        }
    }
}

private struct CalendarBenefitPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.brandBlue.opacity(0.12)))

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }
}

#if canImport(AuthenticationServices)
private struct AppleSignInControl: View {
    @Environment(\.colorScheme) private var scheme
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            onCompletion(result)
        }
        .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .clipShape(Capsule())
    }
}
#endif

private struct OnboardingHeroCard: View {
    @Environment(\.colorScheme) private var scheme
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 16) {
            switch page.visual {
            case .plan:
                PlanPreview()
            case .widget:
                WidgetPreview()
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .frame(height: page.visual == .widget ? 304 : 304)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.84))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(scheme == .dark ? 0.12 : 0.7), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(scheme == .dark ? 0.28 : 0.09), radius: 24, x: 0, y: 14)
    }
}

private struct PlanPreview: View {
    var body: some View {
        VStack(spacing: 10) {
            PreviewInputRow(icon: "keyboard.fill", title: "Quick Add", subtitle: "Essay 60m, laundry, gym", tint: Color.brandBlue, showsClose: true)
            PreviewInputRow(icon: "mic.fill", title: "Plan My Day", subtitle: "Speak a full brain dump", tint: .cyan, showsClose: false)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Preview")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.brandBlue)
                    Spacer()
                    Text("3 tasks")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: 0.66)
                    .tint(Color.brandBlue)

                VStack(spacing: 7) {
                    PreviewDetectedTask(color: Color.brandBlue, title: "Essay", duration: "60m", time: "Today - 2:00 PM")
                    PreviewDetectedTask(color: .purple, title: "Laundry", duration: nil, time: "Today - 5:00 PM")
                    PreviewDetectedTask(color: .orange, title: "Gym", duration: "60m", time: "Today - 7:00 PM")
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.brandBlue.opacity(0.08))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WidgetPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                LaunchLogoImage()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("Sched")
                            .foregroundStyle(.black)
                        Text("AI")
                            .foregroundStyle(Color.brandBlue)
                        Text("Today")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.brandBlue)
                            .padding(.leading, 4)
                    }
                    .font(.headline.weight(.bold))

                    Text("Friday, May 17")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.gray)
                }

                Spacer()

                Image(systemName: "sparkles")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.brandBlue.opacity(0.08)))
            }

            HStack(spacing: 8) {
                WidgetCurrentTask()
                WidgetProgressTile()
            }

            HStack(spacing: 8) {
                WidgetUpcomingList()
                WidgetRemainingTile()
            }

            HStack(spacing: 8) {
                WidgetAction(icon: "mic.fill", title: "Ask SchedAI")
                WidgetAction(icon: "arrow.clockwise", title: "Replan Today")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Color(red: 0.965, green: 0.982, blue: 1.0))
                .shadow(color: Color.white.opacity(0.08), radius: 16, x: 0, y: 0)
        )
    }
}

private struct PreviewInputRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color
    let showsClose: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(tint.opacity(0.13))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                Text(subtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if showsClose {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

private struct PreviewDetectedTask: View {
    let color: Color
    let title: String
    let duration: String?
    let time: String

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)

            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if let duration {
                Text(duration)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.brandBlue.opacity(0.16)))
            }

            Spacer()

            Text(time)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

private struct WidgetCurrentTask: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("NOW")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.brandBlue)
            Text("Workout")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
            Text("9:00 - 9:45 AM")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.gray)
            Text("45m")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.brandBlue.opacity(0.12)))
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.brandBlue.opacity(0.08))
        )
    }
}

private struct WidgetProgressTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("DONE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.brandBlue)

            ZStack {
                Circle()
                    .stroke(Color.brandBlue.opacity(0.14), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: 0.4)
                    .stroke(Color.brandBlue, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("40%")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.black)
                    Text("2 of 5")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 50, height: 50)
        }
        .padding(10)
        .frame(width: 88, alignment: .leading)
        .frame(minHeight: 74, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.brandBlue.opacity(0.06))
        )
    }
}

private struct WidgetUpcomingList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMING UP")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.brandBlue)

            WidgetUpcomingRow(color: Color.brandBlue, title: "Meeting with team", time: "1:00 - 2:00 PM", badge: "60m")
            WidgetUpcomingRow(color: .purple, title: "Dinner", time: "5:00 - 6:00 PM", badge: "60m")
            WidgetUpcomingRow(color: .orange, title: "Study", time: "7:00 - 8:30 PM", badge: "90m")
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.brandBlue.opacity(0.06))
        )
    }
}

private struct WidgetUpcomingRow: View {
    let color: Color
    let title: String
    let time: String
    let badge: String

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2.weight(.bold))
                Text(time)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.gray)
            }
            .foregroundStyle(.black)
            Spacer(minLength: 4)
            Text(badge)
                .font(.caption2.weight(.bold))
                .foregroundStyle(color)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(color.opacity(0.12)))
        }
    }
}

private struct WidgetRemainingTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("REMAINING")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.brandBlue)
            Text("3")
                .font(.title.weight(.bold))
                .foregroundStyle(.black)
            Text("tasks")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.gray)

            Spacer()

            Image(systemName: "list.bullet")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.brandBlue.opacity(0.08))
                )
        }
        .padding(10)
        .frame(width: 88, alignment: .leading)
        .frame(minHeight: 92, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.brandBlue.opacity(0.06))
        )
    }
}

private struct WidgetAction: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.brandBlue)
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .background(
            Capsule()
                .fill(Color.brandBlue.opacity(0.08))
        )
    }
}

private struct LaunchLogoScreen: View {
    var body: some View {
        LaunchBackground {
            VStack(spacing: 18) {
                LaunchLogoImage()

                Text("SchedAI")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }
}

private struct LaunchLogoImage: View {
    var body: some View {
        Group {
            #if canImport(UIKit)
            if let uiImage = UIImage(named: "LauchLogo") {
                Image(uiImage: uiImage)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "calendar.badge.clock")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 84, weight: .semibold))
                    .foregroundStyle(Color.brandBlue)
            }
            #else
            Image(systemName: "calendar.badge.clock")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(Color.brandBlue)
            #endif
        }
        .frame(width: 170, height: 170)
    }
}

private struct LaunchBackground<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            //  ONLY the background changes with light/dark
            if scheme == .dark {
                Color.black.ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [Color(.systemGray6), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            content()
        }
    }
}
