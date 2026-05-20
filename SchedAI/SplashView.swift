//
//  SplashView.swift
//  SchedAI
//
//  Created by Adeoluwa Adekoya on 9/5/25.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct SplashView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    private let onStart: (() -> Void)?

    init(onStart: (() -> Void)? = nil) {
        self.onStart = onStart
    }

    var body: some View {
        SplashBackground {
            VStack(spacing: 24) {
                Spacer(minLength: 42)

                VStack(alignment: .leading, spacing: 10) {
                    Text(welcomeTitle)
                        .font(.system(size: 37, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Ready to shape your day?")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 18) {
                    StartCard()
                        .padding(.horizontal, 24)

                    Button {
                        #if canImport(UIKit)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        #endif
                        onStart?()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "wand.and.stars")
                            Text("Start Planning")
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .background(scheme == .dark ? Color.white : Color.black)
                    .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(scheme == .dark ? 0.32 : 0.12), radius: 16, x: 0, y: 10)
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 26)
            }
        }
    }

    private var welcomeTitle: String {
        if let name = app.userDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return "Welcome back, \(firstName(from: name))"
        }

        return "Welcome back"
    }

    private func firstName(from name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }
}

// MARK: - Card (white in light mode, darker in dark mode but same layout)

private struct StartCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 30, style: .continuous)
            .fill(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.42 : 0.12),
                    radius: scheme == .dark ? 22 : 20,
                    x: 0,
                    y: scheme == .dark ? 10 : 12)
            .frame(height: 374)
            .overlay(cardContent.padding(.horizontal, 20))
    }

    private var cardFill: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.white
    }

    private var borderColor: Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    private var cardContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                LaunchArtworkImage(width: 62, height: 62)

                Text("SchedAI")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Your day, planned clearly.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                StartFeatureRow(icon: "text.badge.plus", title: "Add tasks naturally")
                StartFeatureRow(icon: "checkmark.seal", title: "Preview before changes")
                StartFeatureRow(icon: "bell", title: "Get reminders when it matters")
            }
        }
    }
}

private struct StartFeatureRow: View {
    @Environment(\.colorScheme) private var scheme
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.brandBlue.opacity(scheme == .dark ? 0.16 : 0.1))
                )

            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.86)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.035))
        )
    }
}

private struct LaunchArtworkImage: View {
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
                Image(systemName: "calendar.badge.clock")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            #else
            Image(systemName: "calendar.badge.clock")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.blue)
            #endif
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Background (only thing that changes by mode)

private struct SplashBackground<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ZStack {
            if scheme == .dark {
                LinearGradient(
                    colors: [
                        Color.black,
                        Color(red: 0.025, green: 0.027, blue: 0.032)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            } else {
                LinearGradient(
                    colors: [
                        Color.white,
                        Color(.systemGray6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            content()
        }
    }
}

#Preview {
    SplashView()
}
