import SwiftUI
import Foundation

/// Paste/type multiple tasks (one per line or separated by semicolons),
/// preview them, then add to AppState.
struct AIAddTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let initialInput: String
    let navigationTitle: String
    let onAddComplete: () -> Void

    @State private var input: String = ""
    @State private var isParsing: Bool = false
    @State private var parsedPreview: [TaskItem] = []
    @State private var parseStatusMessage: String? = nil
    @State private var showAIConsentSheet: Bool = false
    @State private var didLoadInitialInput = false

    init(
        initialInput: String = "",
        navigationTitle: String = "Quick Add",
        onAddComplete: @escaping () -> Void = {}
    ) {
        self.initialInput = initialInput
        self.navigationTitle = navigationTitle
        self.onAddComplete = onAddComplete
    }

    private var usesAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    typingInputCard
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    quickAddActions
                        .padding(.horizontal, 16)

                    statusText
                        .padding(.horizontal, 16)

                    if parsedPreview.isEmpty {
                        quickAddTips
                    } else {
                        previewSection
                            .padding(.horizontal, 16)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !didLoadInitialInput else { return }
                didLoadInitialInput = true
                input = initialInput
            }
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

    @ViewBuilder
    private var quickAddActions: some View {
        let inputIsEmpty = input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if usesAccessibilityLayout {
            VStack(spacing: 10) {
                previewButton(disabled: isParsing || inputIsEmpty)
                improveButton(disabled: isParsing || inputIsEmpty)
                addAllButton
            }
        } else {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    previewButton(disabled: isParsing || inputIsEmpty)
                    improveButton(disabled: isParsing || inputIsEmpty)
                }
                addAllButton
            }
        }
    }

    private func previewButton(disabled: Bool) -> some View {
        Button {
            Task { await parsePreview() }
        } label: {
            Label("Preview", systemImage: "eye")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
    }

    private func improveButton(disabled: Bool) -> some View {
        Button {
            requestAIImprove()
        } label: {
            Label(isParsing ? "Using AI" : "Improve", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
    }

    private var addAllButton: some View {
        Button {
            addAllAndDismiss()
        } label: {
            Label("Add All", systemImage: "plus.circle.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(parsedPreview.isEmpty)
    }

    private var statusText: some View {
        Text(parseStatusMessage ?? "Preview stays on device. AI Improve tries Apple Intelligence locally before hosted AI.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var quickAddTips: some View {
        VStack(spacing: 6) {
            Text("Tip: one task per line.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Example: “finish essay 60m urgent”")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preview")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(parsedPreview) { task in
                    QuickAddPreviewRow(task: task, timeFormatter: time)
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
                    Text("Quick Add")
                        .font(.headline.weight(.bold))
                    Text("Type tasks, then preview before adding")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
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
                    .frame(minHeight: usesAccessibilityLayout ? 150 : 172)

                if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Finish essay 60m urgent\nWorkout 45m\nCall mom today")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
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

    private func improvePreviewWithAI(
        allowsHostedAI: Bool? = nil,
        promptForHostedFallback: Bool = false
    ) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isParsing = true
        defer { isParsing = false }

        let result = await AIService.improveTasksWithAI(
            from: trimmed,
            now: Date(),
            planningDate: app.planningDate,
            allowsHostedAI: allowsHostedAI ?? app.hostedAIConsent
        )
        parsedPreview = result.tasks
        parseStatusMessage = result.message ?? (result.source.isAIEnhanced ? "AI improved this preview." : "Offline preview. No credits used.")

        if promptForHostedFallback, result.source == .offline {
            showAIConsentSheet = true
        }
    }

    private func requestAIImprove() {
        Task {
            await improvePreviewWithAI(
                allowsHostedAI: app.hostedAIConsent,
                promptForHostedFallback: !app.hostedAIConsent
            )
        }
    }

    private func addAllAndDismiss() {
        guard !parsedPreview.isEmpty else { return }

        for t in parsedPreview {
            app.addTask(t)
        }

        onAddComplete()
        dismiss()
    }

    private func time(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: d)
    }
}

private struct QuickAddPreviewRow: View {
    let task: TaskItem
    let timeFormatter: (Date) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    metadata
                }

                VStack(alignment: .leading, spacing: 6) {
                    metadata
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var metadata: some View {
        Text("\(task.estimatedMinutes)m")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text(task.priority.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

        if let start = task.scheduledStart, let end = task.scheduledEnd {
            Text("\(timeFormatter(start))-\(timeFormatter(end))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
