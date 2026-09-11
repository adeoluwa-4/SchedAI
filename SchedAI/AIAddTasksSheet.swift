import SwiftUI
import Foundation

/// Paste/type multiple tasks (one per line or separated by semicolons),
/// preview them, then add to AppState.
struct AIAddTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let initialInput: String
    let navigationTitle: String
    let onAddComplete: () -> Void

    @State private var input: String = ""
    @State private var isParsing: Bool = false
    @State private var parsedPreview: [TaskItem] = []
    @State private var parseStatusMessage: String? = nil
    @State private var previewUsedAI = false
    @State private var showAIConsentSheet: Bool = false
    @State private var didLoadInitialInput = false
    @State private var parseRequestID = UUID()
    @State private var previewSource: TaskParseSource = .offline

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
                resetPreviewState()
            }
            .onChange(of: app.planningDate) { _, _ in resetPreviewState() }
            .onDisappear { resetPreviewState() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $showAIConsentSheet) {
                AIConsentSheet {
                    app.hostedAIConsent = true
                    Task { await improvePreviewWithAI(promptForHostedFallback: true) }
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
                addAllButton
            }
        } else {
            VStack(spacing: 10) {
                previewButton(disabled: isParsing || inputIsEmpty)
                addAllButton
            }
        }
    }

    private func previewButton(disabled: Bool) -> some View {
        Button {
            Task { await parsePreview() }
        } label: {
            Label("Preview", systemImage: "wand.and.stars")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(disabled)
    }

    private var addAllButton: some View {
        Button {
            addAllAndDismiss()
        } label: {
            Label("Add tasks", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isParsing || parsedPreview.isEmpty || parsedPreview.contains { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }

    private var statusText: some View {
        Text(isParsing ? "Preparing preview…" : (parseStatusMessage ?? "Preview tries on-device AI first. With your permission, hosted AI may process task text and use your allowance. Offline parsing remains available."))
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
            HStack(spacing: 10) {
                Text("\(parsedPreview.count) task\(parsedPreview.count == 1 ? "" : "s") detected")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                Text(previewSource.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.secondary.opacity(0.16)))
            }

            if !previewUsedAI {
                Button {
                    requestAIImprove()
                } label: {
                    Label(isParsing ? "Using AI" : "Improve with AI", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isParsing || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Text("Tries on-device AI first. Hosted AI requires permission and uses your allowance.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach($parsedPreview) { $task in
                    QuickAddPreviewRow(task: $task, fallbackDay: app.planningDate, findTime: {
                        app.availableTime(for: task, among: parsedPreview)
                    })
                }
            }
            .disabled(isParsing)
            ForEach(Array(app.scheduleWarnings(for: parsedPreview).enumerated()), id: \.offset) { _, warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

        await improvePreviewWithAI()
    }

    private func improvePreviewWithAI(
        allowsHostedAI: Bool? = nil,
        promptForHostedFallback: Bool = false
    ) async {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isParsing = true
        let requestID = UUID()
        parseRequestID = requestID
        let requestedDay = app.planningDate
        defer { if parseRequestID == requestID { isParsing = false } }

        let hasHostedAccess = subscriptions.canUseHostedAI
        let result = await AIService.improveTasksWithAI(
            from: trimmed,
            now: planningReferenceDate,
            planningDate: app.planningDate,
            allowsHostedAI: (allowsHostedAI ?? app.hostedAIConsent) && hasHostedAccess,
            entitlementJWS: subscriptions.entitlementJWS
        )
        if result.source == .ai {
            subscriptions.recordHostedAIUse()
        }
        guard parseRequestID == requestID, input.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed,
              requestedDay == app.planningDate else { return }
        parsedPreview = result.tasks
        previewUsedAI = result.source.isAIEnhanced
        previewSource = result.source

        let hostedAllowanceExhausted = !subscriptions.isPro
            && !hasHostedAccess
            && result.source == .offline
        if hostedAllowanceExhausted {
            parseStatusMessage = "Offline preview. You used today's free hosted AI improvements."
        } else {
            parseStatusMessage = result.source.usageDescription + (result.message.map { " " + $0 } ?? "")
        }

        if promptForHostedFallback, result.source == .offline {
            if !app.hostedAIConsent {
                showAIConsentSheet = true
            } else if result.requiresPro || hostedAllowanceExhausted {
                subscriptions.presentPaywall(.hostedAI)
            }
        }
    }

    private func requestAIImprove() {
        Task {
            await improvePreviewWithAI(
                promptForHostedFallback: true
            )
        }
    }

    private func addAllAndDismiss() {
        guard !isParsing, !parsedPreview.isEmpty,
              !parsedPreview.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return }

        let calendar = Calendar.current
        let fallbackDay = calendar.startOfDay(for: app.planningDate)
        let tasksForPlanningDay = parsedPreview.map { task -> TaskItem in
            var task = task
            if let start = task.scheduledStart {
                task.targetDay = calendar.startOfDay(for: start)
            } else if let target = task.targetDay {
                task.targetDay = calendar.startOfDay(for: target)
            } else {
                task.targetDay = fallbackDay
            }
            return task
        }

        app.addTasks(tasksForPlanningDay)

        onAddComplete()
        dismiss()
    }

    private func resetPreviewState() {
        parseRequestID = UUID()
        isParsing = false
        parsedPreview = []
        parseStatusMessage = nil
        previewUsedAI = false
    }

    private var planningReferenceDate: Date {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: app.planningDate)
        let now = Date()
        if OfflineNLP.hasRelativeCalendarOffset(input) { return now }
        if calendar.isDate(selectedDay, inSameDayAs: now) {
            return now
        }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDay) ?? selectedDay
    }

    private func time(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        return df.string(from: d)
    }
}

private struct QuickAddPreviewRow: View {
    @Binding var task: TaskItem
    let fallbackDay: Date
    let findTime: () -> TaskItem?
    @State private var isEditing = false
    @State private var slotMessage: String?

    private var selectedDate: Date { task.scheduledStart ?? task.targetDay ?? fallbackDay }

    private func setDate(_ date: Date) {
        task.targetDay = Calendar.current.startOfDay(for: date)
        if task.scheduledStart != nil {
            task.scheduledStart = date
            task.scheduledEnd = date.addingTimeInterval(Double(max(5, task.estimatedMinutes)) * 60)
            task.isPinned = true
            task.preferredStart = nil
            task.preferredEnd = nil
        }
    }

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
            Button(isEditing ? "Done editing" : "Edit task") { isEditing.toggle() }
                .buttonStyle(.bordered)
            if isEditing {
                Button("Find available time") {
                    if let suggestion = findTime() {
                        task = suggestion
                        slotMessage = "Suggested time selected. Review it before adding."
                    } else { slotMessage = "No available time on this day. Choose another date or shorten the task." }
                }
                .buttonStyle(.bordered)
                if let slotMessage { Text(slotMessage).font(.caption) }
                TextField("Task title", text: $task.title)
                    .textFieldStyle(.roundedBorder)
                DatePicker("Date", selection: Binding(get: { selectedDate }, set: { newDay in
                    let components = Calendar.current.dateComponents([.hour, .minute], from: selectedDate)
                    setDate(Calendar.current.date(bySettingHour: components.hour ?? 9, minute: components.minute ?? 0,
                                                  second: 0, of: newDay) ?? newDay)
                }), displayedComponents: .date)
                Toggle("Set specific time", isOn: Binding(get: { task.scheduledStart != nil }, set: { enabled in
                    if enabled {
                        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: selectedDate) ?? selectedDate
                        task.scheduledStart = start
                        setDate(start)
                    } else {
                        task.targetDay = Calendar.current.startOfDay(for: selectedDate)
                        task.scheduledStart = nil
                        task.scheduledEnd = nil
                        task.isPinned = false
                    }
                }))
                if task.scheduledStart != nil {
                    DatePicker("Time", selection: Binding(get: { selectedDate }, set: setDate), displayedComponents: .hourAndMinute)
                }
                Stepper("Duration: \(task.estimatedMinutes) min", value: $task.estimatedMinutes, in: 5...480, step: 5)
                    .onChange(of: task.estimatedMinutes) { _, _ in setDate(selectedDate) }
                Picker("Priority", selection: $task.priority) {
                    ForEach(TaskPriority.allCases, id: \.self) { priority in Text(priority.displayName).tag(priority) }
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
        Text(selectedDate.formatted(.dateTime.month(.abbreviated).day().year()))
            .font(.subheadline.weight(.medium))
        Text("\(task.estimatedMinutes)m")
            .font(.caption)
            .foregroundStyle(.secondary)

        Text(task.priority.displayName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

        if let start = task.scheduledStart, let end = task.scheduledEnd {
            Text("\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No time set")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
