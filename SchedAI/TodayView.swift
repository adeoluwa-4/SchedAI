import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Modern, polished "Today" screen with glassmorphic cards and smooth animations
struct TodayView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var showAI = false
    @State private var autoStartOfflineNLPFromWidget = false
    @State private var showOverflowBanner = false
    @State private var overflowHideWorkItem: DispatchWorkItem? = nil
    @State private var showCalendar = false
    @State private var showWorkWindowPicker = false
    @State private var showQuickAdd = false

    private var planningDay: Date {
        Calendar.current.startOfDay(for: app.planningDate)
    }

    private var isPlanningToday: Bool {
        Calendar.current.isDate(planningDay, inSameDayAs: Date())
    }

    private var scheduledToday: [TaskItem] {
        let cal = Calendar.current
        return app.tasks
            .filter { !$0.isCompleted }
            .filter { t in
                guard let s = t.scheduledStart, t.scheduledEnd != nil else { return false }
                return cal.isDate(s, inSameDayAs: planningDay)
            }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
    }

    private var workWindowBounds: (start: Date, end: Date) {
        let cal = Calendar.current
        let day = planningDay

        func combine(_ time: Date) -> Date {
            let dayComps = cal.dateComponents([.year, .month, .day], from: day)
            let t = cal.dateComponents([.hour, .minute, .second], from: time)
            var merged = DateComponents()
            merged.year = dayComps.year
            merged.month = dayComps.month
            merged.day = dayComps.day
            merged.hour = t.hour
            merged.minute = t.minute
            merged.second = t.second
            return cal.date(from: merged) ?? day
        }

        return (combine(app.workStart), combine(app.workEnd))
    }

    private var scheduledInWorkWindow: [TaskItem] {
        let bounds = workWindowBounds
        return scheduledToday.filter { t in
            guard let s = t.scheduledStart else { return false }
            return s >= bounds.start && s < bounds.end
        }
    }

    private var scheduledOutsideWorkWindow: [TaskItem] {
        let bounds = workWindowBounds
        return scheduledToday.filter { t in
            guard let s = t.scheduledStart else { return false }
            return s < bounds.start || s >= bounds.end
        }
    }

    private var primarySchedule: [TaskItem] {
        scheduledInWorkWindow.isEmpty ? scheduledToday : scheduledInWorkWindow
    }

    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: scheme == .dark
                    ? [Color.black, Color(white: 0.05)]
                    : [Color(red: 0.96, green: 0.97, blue: 0.98), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    
                    // MARK: - Header
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: - Main Content
                    if scheduledToday.isEmpty {
                        emptyStateView
                            .padding(.horizontal, 20)
                            .padding(.top, 20)
                    } else {
                        timelineContent
                            .padding(.horizontal, 20)
                    }

                    // MARK: - Overflow Banner
                    if showOverflowBanner && app.lastPlanOverflow > 0 {
                        overflowBannerView
                            .padding(.horizontal, 20)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // MARK: - Action Buttons
                    actionButtons
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    Spacer(minLength: 32)
                }
                .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showAI) {
            AIPlanSheet(autoStartRecording: autoStartOfflineNLPFromWidget)
                .environmentObject(app)
        }
        .sheet(isPresented: $showCalendar) {
            BigCalendarSheet().environmentObject(app)
        }
        .sheet(isPresented: $showWorkWindowPicker) {
            WorkWindowPicker(start: $app.workStart, end: $app.workEnd)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddSheet { text in
                let trimmed = text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let entries = OfflineNLP.splitListEntries(trimmed)
                let inputs = entries.isEmpty ? [trimmed] : entries

                for input in inputs {
                    let parsed = OfflineNLP.parseSafely(input)
                    if parsed.isEmpty { app.addTask(title: input) }
                    else { parsed.forEach { app.addTask($0) } }
                }
                app.planToday(for: planningDay)
            }
        }
        .onAppear {
            updateOverflowBanner()
            handleWidgetVoiceRequestIfNeeded()
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            handleWidgetVoiceRequestIfNeeded()
        }
        #endif
        .onChange(of: showAI) { _, newValue in
            if !newValue {
                autoStartOfflineNLPFromWidget = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppNotifications.widgetVoicePlannerRequested)) { _ in
            openOfflineNLPSheet(autoStartRecording: true)
        }
        .onChange(of: app.lastPlanOverflow) { _ in updateOverflowBanner() }
        .alert("Calendar", isPresented: Binding(
            get: { app.calendarSyncMessage != nil },
            set: { if !$0 { app.calendarSyncMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.calendarSyncMessage ?? "")
        }
    }

    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(isPlanningToday ? "Today" : "Planner")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    Text(formattedDate())
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    ModernIconButton(icon: "calendar", action: {
                        Haptics.medium()
                        showCalendar.toggle()
                    })
                    
                    ModernPrimaryButton(title: "Plan", icon: "sparkles", action: {
                        Haptics.medium()
                        openOfflineNLPSheet(autoStartRecording: false)
                    })
                }
            }
            
            // Stats Cards
            HStack(spacing: 12) {
                StatsCard(
                    icon: "calendar.badge.clock",
                    value: "\(scheduledToday.count)",
                    label: "Scheduled",
                    color: .blue
                )
                
                StatsCard(
                    icon: "list.bullet",
                    value: "\(app.tasks.filter { !$0.isCompleted }.count)",
                    label: "Remaining",
                    color: .orange
                )
                
                StatsCard(
                    icon: "checkmark.circle.fill",
                    value: "\(app.tasks.filter { $0.isCompleted }.count)",
                    label: "Done",
                    color: .green
                )
            }
            
            // Progress Bar
            let totalRemaining = app.tasks.filter { !$0.isCompleted }.count
            let completedCount = app.tasks.filter { $0.isCompleted }.count
            let denom = max(1, totalRemaining + completedCount)
            let progress = Double(completedCount) / Double(denom)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Daily Progress")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                }
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.15))
                        
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * progress)
                            .animation(.spring(response: 0.6, dampingFraction: 0.8), value: progress)
                    }
                }
                .frame(height: 8)
            }
            .padding(.top, 4)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            if app.tasks.isEmpty {
                ModernCard {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.2), .cyan.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(spacing: 8) {
                            Text("Start Your Day")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Add your first tasks and let AI schedule them perfectly")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        HStack(spacing: 12) {
                            Button {
                                Haptics.medium()
                                openOfflineNLPSheet(autoStartRecording: true)
                            } label: {
                                Label("Plan my Day", systemImage: "mic.fill")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ModernPrimaryButtonStyle())
                            
                            Button {
                                Haptics.medium()
                                showQuickAdd.toggle()
                            } label: {
                                Label("Quick Add", systemImage: "plus")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ModernSecondaryButtonStyle())
                        }
                    }
                    .padding(28)
                }
            } else {
                ModernCard {
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [.orange.opacity(0.2), .yellow.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                            
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 36, weight: .semibold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.orange, .yellow],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        VStack(spacing: 8) {
                            Text("\(app.tasks.filter { !$0.isCompleted }.count) Tasks Ready")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("Schedule them into your work window")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        
                        HStack(spacing: 12) {
                            Button {
                                Haptics.medium()
                                openOfflineNLPSheet(autoStartRecording: false)
                            } label: {
                                Label("Auto-Schedule", systemImage: "wand.and.stars")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ModernPrimaryButtonStyle())
                            
                            Button {
                                Haptics.medium()
                                showQuickAdd.toggle()
                            } label: {
                                Label("Add More", systemImage: "plus")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(ModernSecondaryButtonStyle())
                        }
                    }
                    .padding(28)
                }
            }
        }
    }
    
    // MARK: - Timeline Content
    
    private var timelineContent: some View {
        VStack(spacing: 16) {
            // Now/Next Cards
            if let current = currentTask() {
                NowTaskCard(task: current, onComplete: {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        app.toggleComplete(id: current.id)
                    }
                })
            } else if let nextStart = nextStartDate() {
                FreeTimeCard(until: nextStart)
            }
            
            let upcoming = nextTasks(limit: 3)
            if !upcoming.isEmpty {
                UpcomingTasksCard(tasks: upcoming)
            }
            
            // Work Window Tasks
            if !scheduledInWorkWindow.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your Schedule")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 12) {
                        ForEach(scheduledInWorkWindow) { task in
                            ModernTaskCard(task: task, onComplete: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    app.toggleComplete(id: task.id)
                                }
                            })
                        }
                    }
                }
            }
            
            // Outside Work Hours
            if !scheduledOutsideWorkWindow.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("After Hours")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 12) {
                        ForEach(scheduledOutsideWorkWindow) { task in
                            ModernTaskCard(task: task, onComplete: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                    app.toggleComplete(id: task.id)
                                }
                            })
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Overflow Banner
    
    private var overflowBannerView: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(app.lastPlanOverflow) task\(app.lastPlanOverflow == 1 ? "" : "s") didn't fit")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: Color.orange.opacity(0.2), radius: 12, x: 0, y: 4)
    }
    
    // MARK: - Action Buttons
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            if !scheduledToday.isEmpty {
                Button {
                    Haptics.medium()
                    showQuickAdd.toggle()
                } label: {
                    Label("Add Tasks", systemImage: "plus.circle.fill")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernSecondaryButtonStyle())
            }
            
            if !app.tasks.isEmpty {
                Button {
                    Haptics.medium()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        app.planToday(for: planningDay)
                    }
                } label: {
                    Label("Re-plan Day", systemImage: "arrow.clockwise")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(ModernSecondaryButtonStyle())
            }
        }
    }
    
    // MARK: - Helpers
    
    private func updateOverflowBanner() {
        let overflow = app.lastPlanOverflow
        
        overflowHideWorkItem?.cancel()
        overflowHideWorkItem = nil
        
        guard overflow > 0 else {
            withAnimation(.easeOut(duration: 0.2)) { showOverflowBanner = false }
            return
        }
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            showOverflowBanner = true
        }
        
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) { showOverflowBanner = false }
        }
        overflowHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func openOfflineNLPSheet(autoStartRecording: Bool) {
        autoStartOfflineNLPFromWidget = autoStartRecording
        showAI = true
    }

    private func handleWidgetVoiceRequestIfNeeded() {
        guard app.consumeWidgetVoiceRequest() else { return }
        openOfflineNLPSheet(autoStartRecording: true)
    }
    
    private func formattedDate() -> String {
        let df = DateFormatter()
        df.dateFormat = "EEEE, MMMM d"
        return df.string(from: planningDay)
    }
    
    private func currentTask() -> TaskItem? {
        guard isPlanningToday else { return nil }
        let now = Date()
        return primarySchedule.first { task in
            if let s = task.scheduledStart, let e = task.scheduledEnd {
                return s <= now && now < e
            }
            return false
        }
    }
    
    private func nextTasks(limit: Int) -> [TaskItem] {
        let reference = isPlanningToday ? Date() : planningDay
        return Array(primarySchedule.filter { ($0.scheduledStart ?? .distantFuture) > reference }.prefix(limit))
    }
    
    private func nextStartDate() -> Date? {
        nextTasks(limit: 1).first?.scheduledStart
    }
}

// MARK: - Modern Components

private struct ModernCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 20, x: 0, y: 8)
    }
}

private struct StatsCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

private struct ModernIconButton: View {
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
        }
    }
}

private struct ModernPrimaryButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(Capsule())
        }
    }
}

private struct ModernPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct ModernSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct NowTaskCard: View {
    let task: TaskItem
    let onComplete: () -> Void
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Now")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(.blue.opacity(0.15))
                            )
                        
                        Text(task.title)
                            .font(.title3)
                            .fontWeight(.bold)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button(action: onComplete) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                }
                
                if let start = task.scheduledStart, let end = task.scheduledEnd {
                    HStack(spacing: 16) {
                        Label(timeRange(start, end), systemImage: "clock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Label("\(task.estimatedMinutes)m", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
        }
    }
    
    private func timeRange(_ start: Date, _ end: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE, MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return "\(dayFormatter.string(from: start)) • \(timeFormatter.string(from: start))-\(timeFormatter.string(from: end))"
    }
}

private struct FreeTimeCard: View {
    let until: Date
    
    var body: some View {
        ModernCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green.opacity(0.2), .mint.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "figure.walk")
                        .font(.title3)
                        .foregroundStyle(.green)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Free Time")
                        .font(.headline)
                    Text("Until \(until.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .padding(20)
        }
    }
}

private struct UpcomingTasksCard: View {
    let tasks: [TaskItem]
    
    var body: some View {
        ModernCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("Coming Up")
                    .font(.headline)
                
                VStack(spacing: 12) {
                    ForEach(tasks) { task in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.blue.opacity(0.3))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                
                                if let start = task.scheduledStart {
                                    Text(start.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct ModernTaskCard: View {
    let task: TaskItem
    let onComplete: () -> Void
    
    var body: some View {
        ModernCard {
            HStack(spacing: 16) {
                Button(action: onComplete) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.body)
                        .fontWeight(.semibold)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    
                    HStack(spacing: 12) {
                        if let start = task.scheduledStart, let end = task.scheduledEnd {
                            Label(timeRange(start, end), systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Label("\(task.estimatedMinutes)m", systemImage: "timer")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        priorityBadge(task.priority)
                    }
                }
                
                Spacer()
            }
            .padding(16)
        }
    }
    
    private func timeRange(_ start: Date, _ end: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE, MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return "\(dayFormatter.string(from: start)) • \(timeFormatter.string(from: start))–\(timeFormatter.string(from: end))"
    }
    
    @ViewBuilder
    private func priorityBadge(_ priority: TaskPriority) -> some View {
        let config: (String, Color) = {
            switch priority {
            case .high: return ("High", .red)
            case .medium: return ("Med", .orange)
            case .low: return ("Low", .green)
            }
        }()
        
        Text(config.0)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(config.1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(config.1.opacity(0.15))
            )
    }
}
