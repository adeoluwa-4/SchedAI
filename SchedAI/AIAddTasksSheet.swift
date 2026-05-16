import SwiftUI
import Foundation

/// Paste/type multiple tasks (one per line or separated by semicolons),
/// preview them, then add to AppState.
struct AIAddTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme

    @State private var input: String = ""
    @State private var isParsing: Bool = false
    @State private var parsedPreview: [TaskItem] = []
    @State private var parseStatusMessage: String? = nil
    @State private var showAIConsentSheet: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                typingInputCard
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                HStack(spacing: 12) {
                    Button {
                        Task { await parsePreview() }
                    } label: {
                        Label("Preview", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isParsing)

                    Button {
                        requestHostedAIImprove()
                    } label: {
                        Label(isParsing ? "Using AI…" : "Improve", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isParsing || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        addAllAndDismiss()
                    } label: {
                        Label("Add All", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(parsedPreview.isEmpty)
                }
                .padding(.horizontal, 16)

                if let parseStatusMessage {
                    Text(parseStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                } else {
                    Text("Preview stays on device. AI Improve is optional and asks before sending task text off device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }

                if parsedPreview.isEmpty {
                    VStack(spacing: 6) {
                        Text("Tip: one task per line.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Example: “finish essay 60m urgent”")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 10)
                } else {
                    List {
                        Section("Preview") {
                            ForEach(parsedPreview) { t in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(t.title).font(.body)

                                    HStack(spacing: 10) {
                                        Text("\(t.estimatedMinutes)m")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)

                                        Text(t.priority.displayName)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundStyle(.secondary)

                                        if let s = t.scheduledStart, let e = t.scheduledEnd {
                                            Text("\(time(s))–\(time(e))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }

                Spacer(minLength: 10)
            }
            .navigationTitle("Add Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: input) { _, _ in
                parsedPreview = []
                parseStatusMessage = nil
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showAIConsentSheet) {
                AIConsentSheet {
                    app.hostedAIConsent = true
                    Task { await improvePreviewWithAI() }
                }
            }
        }
    }

    private var typingInputCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.blue.opacity(0.16))
                        .frame(width: 42, height: 42)

                    Image(systemName: "keyboard.fill")
                        .font(.headline)
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add Tasks")
                        .font(.headline.weight(.bold))
                    Text("Type one task per line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Typing")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                    )
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $input)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 172)

                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Finish essay 60m urgent\nWorkout 45m\nCall mom today")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.9))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.blue.opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.18 : 0.4), lineWidth: 1)
                    )
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    private func parsePreview() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let result = AIService.parseTasksOffline(from: trimmed, now: Date())
        parsedPreview = result.tasks
        parseStatusMessage = "Offline preview. No credits used."
    }

    private func improvePreviewWithAI() async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isParsing = true
        defer { isParsing = false }

        let result = await AIService.improveTasksWithAI(from: trimmed, now: Date(), planningDate: app.planningDate)
        parsedPreview = result.tasks
        parseStatusMessage = result.message ?? (result.source == .ai ? "AI improved this preview." : "Offline preview. No credits used.")
    }

    private func requestHostedAIImprove() {
        if app.hostedAIConsent {
            Task { await improvePreviewWithAI() }
        } else {
            showAIConsentSheet = true
        }
    }

    private func addAllAndDismiss() {
        if parsedPreview.isEmpty {
            parsedPreview = OfflineNLP.parseSafely(input)
        }
        guard !parsedPreview.isEmpty else { return }

        for t in parsedPreview {
            app.addTask(t)
        }

        dismiss()
    }

    private func time(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: d)
    }
}
