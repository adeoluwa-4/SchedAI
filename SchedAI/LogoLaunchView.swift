import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LogoLaunchView: View {
    private enum Phase { case logo, splash, main }

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
                                phase = .splash
                            }
                        }
                    }

            case .splash:
                SplashView(onStart: {
                    withAnimation(.easeOut(duration: 0.25)) {
                        phase = .main
                    }
                })
                .transition(.opacity)

            case .main:
                ContentView() // Home (Today first tab)
                    .transition(.opacity)
            }
        }
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
