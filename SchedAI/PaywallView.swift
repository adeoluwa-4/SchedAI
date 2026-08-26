import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var subscriptions: SubscriptionManager

    let context: PaywallContext

    var body: some View {
        NavigationStack {
            SubscriptionStoreView(productIDs: SchedAIProduct.allCases.map(\.rawValue)) {
                VStack(spacing: 18) {
                    paywallIcon

                    VStack(spacing: 8) {
                        Text(context.title)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)

                        Text(context.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 12) {
                        PaywallBenefitRow(
                            icon: "sparkles",
                            title: "Expanded hosted AI",
                            subtitle: "Keep Improve available after the daily free allowance."
                        )
                        PaywallBenefitRow(
                            icon: "rectangle.slash",
                            title: "No banner ads",
                            subtitle: "Use Today, Tasks, and Settings without advertising."
                        )
                        PaywallBenefitRow(
                            icon: "lock.shield",
                            title: "Local first",
                            subtitle: "Offline parsing and on-device intelligence remain available without sending task text."
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .subscriptionStoreControlStyle(.prominentPicker)
            .storeButton(.visible, for: .restorePurchases)
            .subscriptionStorePolicyDestination(url: LegalLinks.privacy, for: .privacyPolicy)
            .subscriptionStorePolicyDestination(url: LegalLinks.terms, for: .termsOfService)
            .background(paywallBackground.ignoresSafeArea())
            .navigationTitle("SchedAI Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .onChange(of: subscriptions.isPro) { _, isPro in
                if isPro { dismiss() }
            }
        }
    }

    private var paywallIcon: some View {
        ZStack {
            Circle()
                .fill(Color.brandBlue.opacity(scheme == .dark ? 0.2 : 0.12))
                .frame(width: 86, height: 86)

            Image(systemName: "crown.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.brandBlue)
        }
        .accessibilityHidden(true)
    }

    private var paywallBackground: some View {
        LinearGradient(
            colors: scheme == .dark
                ? [Color.black, Color(white: 0.06)]
                : [Color(red: 0.95, green: 0.97, blue: 1), Color.white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private struct PaywallBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.brandBlue)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.brandBlue.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
