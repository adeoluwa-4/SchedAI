import SwiftUI

struct AIConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let onAccept: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Before using hosted AI")
                            .font(.title2.weight(.bold))

                        Text("Offline preview stays on your device. If you continue with AI Improve, SchedAI sends the task text you typed or spoke, your planning date, locale, time zone, and an offline preview to SchedAI's hosted parser, which uses OpenAI to return structured tasks.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        consentRow(title: "Optional", detail: "You can keep using offline preview without turning this on.")
                        consentRow(title: "Limited purpose", detail: "This is only used to improve task parsing.")
                        consentRow(title: "Your choice", detail: "You can turn hosted AI back off any time in Settings.")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Button("Read Privacy Policy") {
                            openURL(LegalLinks.privacy)
                        }
                        .buttonStyle(.bordered)

                        Button("Review Privacy Choices") {
                            openURL(LegalLinks.privacyChoices)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(20)
            }
            .navigationTitle("AI Consent")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button("Allow AI Improve") {
                        onAccept()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Not Now") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func consentRow(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
