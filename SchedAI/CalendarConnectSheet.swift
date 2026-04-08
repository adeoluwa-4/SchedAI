import SwiftUI

struct CalendarConnectSheet: View {
    let onConnected: () -> Void
    let onDenied: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 68, height: 68)
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.blue)
                }
                .padding(.top, 24)

                // Title & description
                VStack(spacing: 8) {
                    Text("Connect Calendar")
                        .font(.title2).bold()
                        .multilineTextAlignment(.center)
                    Text("Create a dedicated SchedAI calendar to sync your planned schedule. You can remove it anytime in Calendar.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Spacer(minLength: 0)

                // Action buttons
                VStack(spacing: 12) {
                    Button {
                        onConnected()
                        dismiss()
                    } label: {
                        Text("Connect Calendar")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        onDenied()
                        dismiss()
                    } label: {
                        Text("Not Now")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    CalendarConnectSheet(onConnected: {}, onDenied: {})
}
