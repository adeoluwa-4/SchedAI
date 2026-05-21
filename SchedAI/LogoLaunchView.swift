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
        withAnimation(.easeOut(duration: 0.25)) {
            phase = .main
        }
    }

    private func startMainExperience() {
        guard !hasSeenNotificationOnboarding else {
            withAnimation(.easeOut(duration: 0.25)) {
                phase = .main
            }
            return
        }

        NotificationManager.authorizationStatus { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized, .denied:
                    hasSeenNotificationOnboarding = true
                    withAnimation(.easeOut(duration: 0.25)) {
                        phase = .main
                    }
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
    @State private var page = 0
    @State private var hasCompletedAppleSignIn = false
    @State private var needsNameEntry = false
    @State private var firstNameInput = ""
    @State private var signInMessage: String? = nil

    let onFinish: () -> Void

    private let pages = OnboardingPage.pages

    var body: some View {
        OnboardingBackground {
            VStack(spacing: 0) {
                if needsNameEntry {
                    NameEntryOnboardingScreen(firstName: $firstNameInput)
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
        .alert("Sign in required", isPresented: Binding(
            get: { signInMessage != nil },
            set: { if !$0 { signInMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInMessage ?? "")
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
            } else if hasCompletedAppleSignIn {
                Button {
                    if page == pages.count - 1 {
                        onFinish()
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            page += 1
                        }
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(page == pages.count - 1 ? "Start Planning" : "Continue")
                        Image(systemName: page == pages.count - 1 ? "checkmark" : "arrow.right")
                    }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
            } else {
                #if canImport(AuthenticationServices)
                AppleSignInControl(onCompletion: handleAppleSignInResult)
                #else
                Button {
                    signInMessage = "Sign in with Apple is unavailable on this device, so onboarding cannot continue here."
                } label: {
                    Text("Sign in with Apple")
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.brandBlue)
                #endif
            }
        }
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
                    hasCompletedAppleSignIn = true
                    page = 0
                }
            }
        case .failure:
            signInMessage = "Sign in with Apple was cancelled or failed. It is required to continue."
        }
    }
    #else
    private func handleAppleSignInResult(_ result: Result<Void, Error>) {
        signInMessage = "Sign in with Apple is unavailable on this device, so onboarding cannot continue here."
    }
    #endif

    private func saveManualFirstName() {
        let name = firstNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        app.userDisplayName = name
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            needsNameEntry = false
            hasCompletedAppleSignIn = true
            page = 0
        }
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
            subtitle: "SchedAI turns your tasks into a preview first, so you stay in control before anything changes.",
            visual: .plan
        ),
        OnboardingPage(
            icon: "square.grid.2x2",
            eyebrow: "Stay oriented",
            title: "Keep today in view.",
            subtitle: "Add the widget after setup to see what is happening now, what is coming next, and what is left.",
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
        VStack(spacing: 24) {
            Spacer(minLength: 34)

            OnboardingHeroCard(page: page)

            VStack(spacing: 12) {
                Text(page.eyebrow.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.brandBlue)

                Text(page.title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
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

                if page.visual == .widget {
                    WidgetSetupInstruction()
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 12)
        }
    }
}

private struct WidgetSetupInstruction: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("How to add it after setup", systemImage: "square.grid.2x2")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.brandBlue)

            HStack(spacing: 8) {
                WidgetInstructionStep(number: "1", text: "Hold Home Screen")
                WidgetInstructionStep(number: "2", text: "Tap +")
                WidgetInstructionStep(number: "3", text: "Search SchedAI")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.brandBlue.opacity(0.12), lineWidth: 1)
                )
        )
    }
}

private struct WidgetInstructionStep: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(number)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.brandBlue))

            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

                    Text("Sign in to personalize SchedAI and continue setup.")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .lineSpacing(3)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 310)
                }

                HStack(spacing: 10) {
                    Image(systemName: "lock.shield")
                    Text("Your Apple name stays local on this device.")
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
        .frame(height: 260)
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
        VStack(spacing: 12) {
            PreviewTaskRow(icon: "keyboard.fill", title: "Quick Add", subtitle: "Essay 60m, laundry, gym", tint: .blue)
            PreviewTaskRow(icon: "mic.fill", title: "Plan My Day", subtitle: "Speak a full brain dump", tint: .cyan)

            VStack(alignment: .leading, spacing: 8) {
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
            }
            .padding(14)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                LaunchLogoImage()
                    .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SchedAI")
                        .font(.headline.weight(.bold))
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.brandBlue)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
            }

            HStack(spacing: 10) {
                WidgetMetric(title: "NOW", value: "Workout", footnote: "45m")
                WidgetMetric(title: "DONE", value: "40%", footnote: "2 of 5")
            }

            WidgetMetric(title: "COMING UP", value: "Meeting with team", footnote: "1:00 PM")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.86))
        )
    }
}

private struct PreviewTaskRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
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
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

private struct WidgetMetric: View {
    let title: String
    let value: String
    let footnote: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.brandBlue)
            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.black)
                .lineLimit(1)
            Text(footnote)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.gray)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
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
