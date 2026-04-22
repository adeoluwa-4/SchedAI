import SwiftUI

struct AIPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    let autoStartRecording: Bool

    @StateObject private var speech = SpeechRecognizer()
    @State private var transcript: String = ""
    @State private var isAuthorized = false
    @State private var previewBase: [TaskItem] = []
    @State private var parsedPreview: [TaskItem] = []
    @State private var previewDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var needsInlineDaySelector = false
    @State private var expandedPreviewTaskIDs: Set<UUID> = []
    @State private var hasManualPreviewEdits = false
    @State private var isPlanning = false
    @State private var animateLoader = false
    @State private var didAutoStartRecording = false

    init(autoStartRecording: Bool = false) {
        self.autoStartRecording = autoStartRecording
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 16) {
                    Text("Tap the microphone and speak your tasks. I’ll plan them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.thinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(.quaternary, lineWidth: 1)
                            )

                        VStack(spacing: 12) {
                            ScrollView {
                                Text(transcript.isEmpty ? "Say something like: ‘finish essay 60m urgent, then gym 1h’" : transcript)
                                    .font(.body)
                                    .foregroundStyle(transcript.isEmpty ? .secondary : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                            }
                            .frame(minHeight: 140)

                            HStack(spacing: 16) {
                                Button(action: toggleRecord) {
                                    ZStack {
                                        Circle().fill(speech.isRecording ? Color.red.opacity(0.15) : Color.blue.opacity(0.15))
                                            .frame(width: 76, height: 76)
                                        Image(systemName: speech.isRecording ? "stop.fill" : "mic.fill")
                                            .font(.system(size: 28, weight: .bold))
                                            .foregroundStyle(speech.isRecording ? .red : .blue)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(speech.isRecording ? "Stop recording" : "Start recording")
                                .disabled(isPlanning)

                                VStack(alignment: .leading, spacing: 6) {
                                    Text(speech.isRecording ? "Listening…" : (isAuthorized ? "Ready" : "Needs permission"))
                                        .font(.headline)
                                    Text(isAuthorized ? "" : "Allow Speech Recognition to use voice planning")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                        }
                        .padding(12)
                    }

                    HStack(spacing: 12) {
                        Button {
                            transcript = ""
                            previewBase = []
                            parsedPreview = []
                            needsInlineDaySelector = false
                            expandedPreviewTaskIDs.removeAll()
                            hasManualPreviewEdits = false
                        } label: {
                            Label("Clear", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPlanning)

                        Button(action: buildPreview) {
                            Label("Preview", systemImage: "wand.and.stars")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPlanning)
                    }

                    if !parsedPreview.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("SchedAI detected \(parsedPreview.count) task\(parsedPreview.count == 1 ? "" : "s"):")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if needsInlineDaySelector {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Schedule untimed tasks for:")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                    DatePicker(
                                        "Plan date",
                                        selection: $previewDay,
                                        displayedComponents: [.date]
                                    )
                                    .labelsHidden()
                                }
                            }

                            Text("Planning for \(day(previewDay))")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(Array(parsedPreview.indices), id: \.self) { idx in
                                let task = parsedPreview[idx]
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(task.title)
                                            .font(.body)
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                        Text(scheduleSummary(task))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.trailing)

                                        Button(expandedPreviewTaskIDs.contains(task.id) ? "Done" : "Edit") {
                                            if expandedPreviewTaskIDs.contains(task.id) {
                                                expandedPreviewTaskIDs.remove(task.id)
                                            } else {
                                                expandedPreviewTaskIDs.insert(task.id)
                                            }
                                        }
                                        .font(.caption.weight(.semibold))
                                        .buttonStyle(.bordered)
                                    }

                                    if expandedPreviewTaskIDs.contains(task.id) {
                                        VStack(alignment: .leading, spacing: 8) {
                                            Picker("Priority", selection: previewPriorityBinding(at: idx)) {
                                                ForEach(TaskPriority.allCases, id: \.self) { level in
                                                    Text(level.displayName).tag(level)
                                                }
                                            }
                                            .pickerStyle(.segmented)

                                            DatePicker(
                                                "Day",
                                                selection: previewDayBinding(at: idx),
                                                displayedComponents: [.date]
                                            )

                                            Toggle("Set specific time", isOn: previewHasTimeBinding(at: idx))

                                            if parsedPreview[idx].scheduledStart != nil {
                                                DatePicker(
                                                    "Time",
                                                    selection: previewTimeBinding(at: idx),
                                                    displayedComponents: [.hourAndMinute]
                                                )
                                            }
                                        }
                                        .padding(.top, 4)
                                    }
                                }
                                .padding(.vertical, 4)
                            }

                            Button(action: confirmPlan) {
                                Text("Confirm Plan")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isPlanning)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.thinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding(16)

                if isPlanning {
                    ZStack {
                        Color.black.opacity(0.32)
                            .ignoresSafeArea()

                        VStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.16))
                                    .frame(width: 92, height: 92)
                                    .scaleEffect(animateLoader ? 1.08 : 0.92)
                                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: animateLoader)

                                Image(systemName: "sparkles")
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundStyle(.blue)
                                    .rotationEffect(.degrees(animateLoader ? 360 : 0))
                                    .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: animateLoader)
                            }

                            Text("Making plan…")
                                .font(.headline)
                            Text("Organizing your tasks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                    }
                    .transition(.opacity)
                }
            }
            .navigationTitle("Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isPlanning)
                }
            }
            .task { await setupPermissions() }
            .onReceive(speech.$transcript) { text in
                self.transcript = text
                self.previewBase = []
                self.parsedPreview = []
                self.needsInlineDaySelector = false
                self.expandedPreviewTaskIDs.removeAll()
                self.hasManualPreviewEdits = false
            }
            .onChange(of: app.planningDate) { _, newValue in
                if previewBase.isEmpty {
                    previewDay = Calendar.current.startOfDay(for: newValue)
                }
            }
            .onChange(of: previewDay) { _, newValue in
                guard !previewBase.isEmpty, needsInlineDaySelector else { return }
                guard !hasManualPreviewEdits else { return }
                parsedPreview = autoPlace(previewBase, on: newValue)
            }
        }
    }

    // MARK: - Actions

    private func setupPermissions() async {
        let ok = await speech.ensureAuthorized()
        await MainActor.run {
            isAuthorized = ok
            previewDay = Calendar.current.startOfDay(for: app.planningDate)
            maybeAutoStartRecording()
        }
    }

    private func maybeAutoStartRecording() {
        guard autoStartRecording else { return }
        guard isAuthorized else { return }
        guard !didAutoStartRecording else { return }
        guard !speech.isRecording else { return }

        didAutoStartRecording = true
        speech.start { text in
            self.transcript = text
        }
    }

    private func toggleRecord() {
        if speech.isRecording {
            speech.stop()
        } else {
            if isAuthorized {
                speech.start { text in
                    self.transcript = text
                }
            }
        }
    }

    private func buildPreview() {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let items = OfflineNLP.parseSafely(text)

        let base: [TaskItem]
        if items.isEmpty {
            base = [TaskItem(title: text, estimatedMinutes: 30, priority: .medium)]
        } else {
            base = items
        }

        let hasUntimed = base.contains { $0.scheduledStart == nil }
        let hasExplicitDay = OfflineNLP.hasExplicitDayReference(text)
        needsInlineDaySelector = hasUntimed && !hasExplicitDay

        let inferredDay = base.compactMap(\.scheduledStart).first.map { Calendar.current.startOfDay(for: $0) }
        previewDay = inferredDay ?? Calendar.current.startOfDay(for: app.planningDate)

        previewBase = base
        expandedPreviewTaskIDs.removeAll()
        hasManualPreviewEdits = false
        parsedPreview = autoPlace(base, on: previewDay)
    }

    private func confirmPlan() {
        guard !parsedPreview.isEmpty else { return }
        isPlanning = true
        animateLoader = true

        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                let targetDay = Calendar.current.startOfDay(for: previewDay)
                let finalPreview = autoPlace(parsedPreview, on: targetDay)
                finalPreview.forEach { app.addTask($0) }
                app.setPlanningDate(targetDay)
                app.planToday(for: targetDay)
                dismiss()
            }
        }
    }

    private func autoPlace(_ tasks: [TaskItem], on day: Date) -> [TaskItem] {
        var working = tasks
        let cal = Calendar.current
        let fallbackDay = cal.startOfDay(for: day)

        for i in working.indices {
            if let start = working[i].scheduledStart {
                working[i].targetDay = cal.startOfDay(for: start)
            } else if let target = working[i].targetDay {
                working[i].targetDay = cal.startOfDay(for: target)
            } else {
                working[i].targetDay = fallbackDay
            }
        }

        let planningDays = Array(Set(working.compactMap(\.targetDay))).sorted()
        for planningDay in planningDays {
            let externalBusy = CalendarManager.shared.busyIntervals(on: planningDay) ?? []
            _ = Scheduler.planToday(
                tasks: &working,
                workStart: app.workStart,
                workEnd: app.workEnd,
                day: planningDay,
                externalBusyIntervals: externalBusy
            )
        }
        return working
    }

    private func previewPriorityBinding(at index: Int) -> Binding<TaskPriority> {
        Binding(
            get: { parsedPreview[index].priority },
            set: { newValue in
                parsedPreview[index].priority = newValue
                hasManualPreviewEdits = true
            }
        )
    }

    private func previewDayBinding(at index: Int) -> Binding<Date> {
        Binding(
            get: { dayForPreviewTask(parsedPreview[index]) },
            set: { newValue in
                let cal = Calendar.current
                let selectedDay = cal.startOfDay(for: newValue)
                parsedPreview[index].targetDay = selectedDay

                if let start = parsedPreview[index].scheduledStart {
                    let timeComps = cal.dateComponents([.hour, .minute], from: start)
                    var comps = cal.dateComponents([.year, .month, .day], from: selectedDay)
                    comps.hour = timeComps.hour ?? 9
                    comps.minute = timeComps.minute ?? 0
                    comps.second = 0

                    let newStart = cal.date(from: comps) ?? start
                    parsedPreview[index].scheduledStart = newStart
                    parsedPreview[index].scheduledEnd = cal.date(
                        byAdding: .minute,
                        value: max(5, parsedPreview[index].estimatedMinutes),
                        to: newStart
                    )
                }

                hasManualPreviewEdits = true
            }
        )
    }

    private func previewHasTimeBinding(at index: Int) -> Binding<Bool> {
        Binding(
            get: { parsedPreview[index].scheduledStart != nil },
            set: { enabled in
                let cal = Calendar.current
                let day = dayForPreviewTask(parsedPreview[index])

                if enabled {
                    let start = parsedPreview[index].scheduledStart ?? combine(day: day, hour: 9, minute: 0)
                    parsedPreview[index].isPinned = true
                    parsedPreview[index].targetDay = cal.startOfDay(for: day)
                    parsedPreview[index].scheduledStart = start
                    parsedPreview[index].scheduledEnd = cal.date(
                        byAdding: .minute,
                        value: max(5, parsedPreview[index].estimatedMinutes),
                        to: start
                    )
                } else {
                    parsedPreview[index].isPinned = false
                    parsedPreview[index].targetDay = cal.startOfDay(for: day)
                    parsedPreview[index].scheduledStart = nil
                    parsedPreview[index].scheduledEnd = nil
                }

                hasManualPreviewEdits = true
            }
        )
    }

    private func previewTimeBinding(at index: Int) -> Binding<Date> {
        Binding(
            get: {
                parsedPreview[index].scheduledStart
                    ?? combine(day: dayForPreviewTask(parsedPreview[index]), hour: 9, minute: 0)
            },
            set: { newTime in
                let cal = Calendar.current
                let day = dayForPreviewTask(parsedPreview[index])
                let timeComps = cal.dateComponents([.hour, .minute], from: newTime)
                var comps = cal.dateComponents([.year, .month, .day], from: day)
                comps.hour = timeComps.hour ?? 9
                comps.minute = timeComps.minute ?? 0
                comps.second = 0

                let start = cal.date(from: comps) ?? newTime
                parsedPreview[index].isPinned = true
                parsedPreview[index].targetDay = cal.startOfDay(for: day)
                parsedPreview[index].scheduledStart = start
                parsedPreview[index].scheduledEnd = cal.date(
                    byAdding: .minute,
                    value: max(5, parsedPreview[index].estimatedMinutes),
                    to: start
                )
                hasManualPreviewEdits = true
            }
        )
    }

    private func dayForPreviewTask(_ task: TaskItem) -> Date {
        let cal = Calendar.current
        if let start = task.scheduledStart {
            return cal.startOfDay(for: start)
        }
        if let target = task.targetDay {
            return cal.startOfDay(for: target)
        }
        return cal.startOfDay(for: previewDay)
    }

    private func combine(day: Date, hour: Int, minute: Int) -> Date {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return cal.date(from: comps) ?? day
    }

    private func scheduleSummary(_ task: TaskItem) -> String {
        if let start = task.scheduledStart, let end = task.scheduledEnd {
            return "\(day(start)) • \(time(start))-\(time(end))"
        }
        if let target = task.targetDay {
            return "\(day(target)) • Flexible"
        }
        return "Flexible"
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: date)
    }
}
