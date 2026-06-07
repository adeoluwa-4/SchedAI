import SwiftUI

struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                sheetBackground

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ConsentHero()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("What happens when this is on")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            ConsentFeatureRow(
                                icon: "iphone",
                                title: "Local first",
                                detail: "SchedAI tries offline parsing and on-device Apple Intelligence before hosted AI."
                            )

                            ConsentFeatureRow(
                                icon: "text.badge.checkmark",
                                title: "Only the planning text",
                                detail: "Hosted AI receives the task text you typed or spoke, planning date, locale, time zone, an offline preview, and a random SchedAI client id."
                            )

                            ConsentFeatureRow(
                                icon: "sparkles",
                                title: "Used for Improve",
                                detail: "The hosted parser uses OpenAI to return structured tasks when you choose AI Improve."
                            )

                            ConsentFeatureRow(
                                icon: "slider.horizontal.3",
                                title: "Your control",
                                detail: "You can turn hosted AI Improve off again in Settings at any time."
                            )
                        }

                        VStack(spacing: 10) {
                            ConsentLinkButton(title: "Privacy Policy", icon: "hand.raised") {
                                openURL(LegalLinks.privacy)
                            }

                            ConsentLinkButton(title: "Privacy Choices", icon: "slider.horizontal.3") {
                                openURL(LegalLinks.privacyChoices)
                            }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 126)
                }
            }
            .navigationTitle("AI Improve")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button {
                        onAccept()
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                            Text("Allow Hosted AI Improve")
                        }
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.brandBlue)

                    Button {
                        dismiss()
                    } label: {
                        Text("Not Now")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var sheetBackground: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color.black, Color(red: 0.02, green: 0.04, blue: 0.08)]
                : [Color(red: 0.96, green: 0.98, blue: 1.0), Color.white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private struct ConsentHero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.brandBlue.opacity(0.12))
                    .frame(width: 64, height: 64)

                Image(systemName: "sparkles.rectangle.stack")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color.brandBlue)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Use hosted AI only when you choose it.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Hosted AI Improve can make messy task dumps easier to structure. You can turn it off later in Settings.")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        )
    }
}

private struct ConsentFeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.brandBlue.opacity(0.12)))

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(detail)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
    }
}

private struct ConsentLinkButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.brandBlue)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.brandBlue.opacity(0.12)))

                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }
}
