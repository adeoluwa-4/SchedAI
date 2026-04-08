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
    private let onStart: (() -> Void)?

    init(onStart: (() -> Void)? = nil) {
        self.onStart = onStart
    }

    var body: some View {
        SplashBackground {
            VStack(spacing: 18) {
                Spacer(minLength: 8)

                // Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(greeting())
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Let’s plan your day.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)

                Spacer()

                // Card + Button stack
                VStack(spacing: 18) {
                    StartCard()
                        .padding(.horizontal, 20)

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
                        .font(.headline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    }
                    .background(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.95), Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 28)
            }
        }
    }

    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }
}

// MARK: - Card (white in light mode, darker in dark mode but same layout)

private struct StartCard: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(cardFill)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(scheme == .dark ? 0.35 : 0.18),
                    radius: scheme == .dark ? 18 : 22,
                    x: 0,
                    y: scheme == .dark ? 10 : 12)
            .frame(height: 260)
            .overlay(cardContent.padding(.horizontal, 20))
    }

    private var cardFill: Color {
        scheme == .dark ? Color(.secondarySystemBackground) : Color.white
    }

    private var borderColor: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var cardContent: some View {
        VStack(spacing: 14) {
            LaunchArtworkImage(width: 140, height: 140)

            Text("SchedAI")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(scheme == .dark ? .white : .black)

            Text("Your personal AI-powered day planner.")
                .font(.callout)
                .foregroundStyle(scheme == .dark ? .white.opacity(0.65) : .black.opacity(0.45))
        }
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
                Color.black.ignoresSafeArea()
            } else {
                // ✅ matches the light screenshot: soft gray background
                LinearGradient(
                    colors: [
                        Color(.systemGray5).opacity(0.55),
                        Color(.systemGray6)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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
