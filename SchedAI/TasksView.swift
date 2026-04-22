import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.colorScheme) private var scheme
    @State private var newTitle = ""
    @State private var editingTask: TaskItem?
    @State private var filter: TaskFilter = .all
    @State private var showCompleted: Bool = false
    
    private enum TaskFilter: String, CaseIterable {
        case all, unscheduled, scheduled, high
        
        var label: String {
            switch self {
            case .all: return "All"
            case .unscheduled: return "Unscheduled"
            case .scheduled: return "Scheduled"
            case .high: return "High Priority"
                        }
        }
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .unscheduled: return "clock.badge.questionmark"
            case .scheduled: return "calendar.badge.clock"
            case .high: return "exclamationmark.triangle.fill"
            }
        }
    }
    
    private var activeTasks: [TaskItem] { app.tasks.filter { !$0.isCompleted } }
    private var completedTasks: [TaskItem] { app.tasks.filter { $0.isCompleted } }
    private var unscheduledActiveCount: Int {
        activeTasks.filter { $0.scheduledStart == nil || $0.scheduledEnd == nil }.count
    }
    
    private var displayedActiveTasks: [TaskItem] {
        switch filter {
        case .all:
            return activeTasks
        case .unscheduled:
            return activeTasks.filter { $0.scheduledStart == nil || $0.scheduledEnd == nil }
        case .scheduled:
            return activeTasks.filter { $0.scheduledStart != nil && $0.scheduledEnd != nil }
        case .high:
            return activeTasks.filter { $0.priority == .high }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
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
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Tasks")
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                        // MARK: - Quick Add
                        quickAddSection
                            .padding(.horizontal, 20)
                        
                        // MARK: - Filter Chips
                        filterSection
                            .padding(.horizontal, 20)
                        
                        // MARK: - Active Tasks
                        activeTasksSection
                            .padding(.horizontal, 20)
                        
                        // MARK: - Completed Tasks
                        if !completedTasks.isEmpty {
                            completedTasksSection
                                .padding(.horizontal, 20)
                        }
                        
                        Spacer(minLength: 80)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if activeTasks.count > 0 {
                    planButton
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: scheme == .dark
                                    ? [Color(white: 0.1), Color.black]
                                    : [Color.white.opacity(0.95), Color(red: 0.96, green: 0.97, blue: 0.98)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea()
                        )
                }
            }
            .sheet(item: $editingTask) { task in
                TaskEditView(task: task)
                    .environmentObject(app)
            }
        }
    }
    
    // MARK: - Quick Add Section
    
    private var quickAddSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                TextField("e.g., finish essay 60m urgent", text: $newTitle)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit(addTask)
                
                if !newTitle.isEmpty {
                    Button(action: { newTitle = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: addTask) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(newTitle.isEmpty ? Color.secondary : Color.blue)
                }
                .disabled(newTitle.isEmpty)
                .buttonStyle(.plain)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
            
            // Helper chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    QuickChip(icon: "clock", label: "15m") { appendToQuickAdd("15m") }
                    QuickChip(icon: "clock", label: "30m") { appendToQuickAdd("30m") }
                    QuickChip(icon: "clock", label: "1h") { appendToQuickAdd("1h") }
                    QuickChip(icon: "exclamationmark.triangle", label: "Urgent") { appendToQuickAdd("urgent") }
                    QuickChip(icon: "calendar", label: "Today") { appendToQuickAdd("today") }
                }
            }
        }
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TaskFilter.allCases, id: \.self) { filterOption in
                        FilterChip(
                            icon: filterOption.icon,
                            label: filterOption.label,
                            isSelected: filter == filterOption
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                filter = filterOption
                            }
                        }
                    }
                }
            }
            
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(displayedActiveTasks.count) active tasks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
    
    // MARK: - Active Tasks Section
    
    private var activeTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Active")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.horizontal, 4)
            
            if displayedActiveTasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 12) {
                    ForEach(displayedActiveTasks) { task in
                        ModernTaskRow(
                            task: task,
                            onToggle: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    app.toggleComplete(id: task.id)
                                }
                            },
                            onEdit: { editingTask = task },
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    app.deleteTask(id: task.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }
    
    // MARK: - Completed Tasks Section
    
    private var completedTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showCompleted.toggle()
                }
            } label: {
                HStack {
                    Text("Completed")
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("(\(completedTasks.count))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: showCompleted ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            if showCompleted {
                VStack(spacing: 12) {
                    ForEach(completedTasks) { task in
                        CompletedTaskRow(
                            task: task,
                            onToggle: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                                    app.toggleComplete(id: task.id)
                                }
                            },
                            onEdit: { editingTask = task },
                            onDelete: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    app.deleteTask(id: task.id)
                                }
                            }
                        )
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.15), .cyan.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                
                Image(systemName: filter.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)
            }
            
            VStack(spacing: 6) {
                Text("No \(filter.label) Tasks")
                    .font(.headline)
                
                Text("Try changing filters or add a new task")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Plan Button
    
    private var planButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                if unscheduledActiveCount > 0 {
                    app.planUnscheduledOnly(for: app.planningDate)
                } else {
                    app.planToday(for: app.planningDate)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(buttonTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.blue.opacity(0.3), radius: 12, x: 0, y: 6)
        }
    }

    private var buttonTitle: String {
        if unscheduledActiveCount > 0 {
            return "Schedule Today (\(unscheduledActiveCount))"
        }
        return "Replan Today (\(activeTasks.count))"
    }
    
    // MARK: - Helpers
    
    private func addTask() {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let parsed = OfflineNLP.parseSafely(trimmed)
        if parsed.isEmpty {
            app.addTask(title: trimmed)
        } else {
            parsed.forEach { app.addTask($0) }
        }
        
        newTitle = ""
        Haptics.medium()
    }
    
    private func appendToQuickAdd(_ token: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { newTitle = token }
        else { newTitle = trimmed + " " + token }
    }
}

// MARK: - Components

private struct QuickChip: View {
    let icon: String
    let label: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct FilterChip: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ?
                          LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing) :
                          LinearGradient(colors: [Color.clear], startPoint: .leading, endPoint: .trailing)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.clear : Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ModernTaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        let rowContent = HStack(spacing: 16) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if task.isCompleted {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.green, .mint],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                
                HStack(spacing: 10) {
                    if let start = task.scheduledStart, let end = task.scheduledEnd {
                        Label(timeRange(start, end), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Label("\(task.estimatedMinutes)m", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    PriorityBadge(priority: task.priority)
                }
            }
            
            Spacer()
            
            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        
        return SwipeableRow(
            content: { rowContent },
            leadingAction: onToggle,
            leadingLabel: "Complete",
            leadingSystemImage: "checkmark",
            leadingTint: .green,
            trailingAction: onDelete,
            trailingLabel: "Delete",
            trailingSystemImage: "trash",
            trailingTint: .red
        )
    }
    
    private func timeRange(_ start: Date, _ end: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE, MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return "\(dayFormatter.string(from: start)) • \(timeFormatter.string(from: start))–\(timeFormatter.string(from: end))"
    }
}

private struct CompletedTaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        let rowContent = HStack(spacing: 16) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.green, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .strikethrough()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                
                HStack(spacing: 10) {
                    if let start = task.scheduledStart, let end = task.scheduledEnd {
                        Label(timeRange(start, end), systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Label("\(task.estimatedMinutes)m", systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            
            Spacer()
            
            Menu {
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.ultraThinMaterial))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .opacity(0.7)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        
        return SwipeableRow(
            content: { rowContent },
            leadingAction: onToggle,
            leadingLabel: "Mark Active",
            leadingSystemImage: "checkmark",
            leadingTint: .green,
            trailingAction: onDelete,
            trailingLabel: "Delete",
            trailingSystemImage: "trash",
            trailingTint: .red
        )
    }
    
    private func timeRange(_ start: Date, _ end: Date) -> String {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE, MMM d"
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        return "\(dayFormatter.string(from: start)) • \(timeFormatter.string(from: start))–\(timeFormatter.string(from: end))"
    }
}

private struct SwipeableRow<Content: View>: View {
    let content: Content
    let leadingAction: (() -> Void)?
    let leadingLabel: String
    let leadingSystemImage: String
    let leadingTint: Color
    let trailingAction: (() -> Void)?
    let trailingLabel: String
    let trailingSystemImage: String
    let trailingTint: Color
    
    @State private var offset: CGFloat = 0
    @GestureState private var translation: CGSize = .zero
    
    private let actionWidth: CGFloat = 80
    private let fullSwipe: CGFloat = 120
    
    private var progress: CGFloat {
        let total = offset + translation.width
        if total >= 0 {
            return min(1, max(0, total / actionWidth))
        } else {
            return min(1, max(0, -total / actionWidth))
        }
    }
    
    init(
        @ViewBuilder content: () -> Content,
        leadingAction: (() -> Void)? = nil,
        leadingLabel: String = "",
        leadingSystemImage: String = "",
        leadingTint: Color = .green,
        trailingAction: (() -> Void)? = nil,
        trailingLabel: String = "",
        trailingSystemImage: String = "",
        trailingTint: Color = .red
    ) {
        self.content = content()
        self.leadingAction = leadingAction
        self.leadingLabel = leadingLabel
        self.leadingSystemImage = leadingSystemImage
        self.leadingTint = leadingTint
        self.trailingAction = trailingAction
        self.trailingLabel = trailingLabel
        self.trailingSystemImage = trailingSystemImage
        self.trailingTint = trailingTint
    }
    
    var body: some View {
        ZStack {
            // Background actions (rounded, animated)
            HStack(spacing: 0) {
                if leadingAction != nil {
                    leadingPill
                        .frame(width: max(actionWidth * progress, 0))
                        .opacity(progress)
                        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: progress)
                } else {
                    Spacer().frame(width: 0)
                }
                
                Spacer(minLength: 0)
                
                if trailingAction != nil {
                    trailingPill
                        .frame(width: max(actionWidth * progress, 0))
                        .opacity(progress)
                        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: progress)
                } else {
                    Spacer().frame(width: 0)
                }
            }
            
            content
                .offset(x: offset + translation.width)
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .local)
                        .updating($translation) { value, state, _ in
                            let proposed = value.translation.width
                            if proposed > 0 {
                                state = CGSize(width: min(proposed, actionWidth * 1.4), height: 0)
                            } else {
                                state = CGSize(width: max(proposed, -actionWidth * 1.4), height: 0)
                            }
                        }
                        .onEnded { value in
                            let total = offset + value.translation.width
                            handleEnd(total)
                        }
                )
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: offset)
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: translation)
        }
        .clipped()
    }
    
    private var leadingPill: some View {
        let scale = 0.8 + 0.4 * progress
        return ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(leadingTint)
                .shadow(color: leadingTint.opacity(0.25), radius: 8, x: 0, y: 4)
            Button(action: { triggerLeading(); offset = 0 }) {
                Image(systemName: leadingSystemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(scale)
                    .opacity(0.6 + 0.4 * progress)
                    .frame(width: actionWidth, height: 56, alignment: .center)
            }
            .buttonStyle(.plain)
        }
    }
    
    private var trailingPill: some View {
        let scale = 0.8 + 0.4 * progress
        return ZStack(alignment: .trailing) {
            Capsule(style: .continuous)
                .fill(trailingTint)
                .shadow(color: trailingTint.opacity(0.25), radius: 8, x: 0, y: 4)
            Button(action: { triggerTrailing(); offset = 0 }) {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(scale)
                    .opacity(0.6 + 0.4 * progress)
                    .frame(width: actionWidth, height: 56, alignment: .center)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func handleEnd(_ total: CGFloat) {
        // Full-swipe triggers the action and snaps back
        if total > fullSwipe, let leadingAction {
            Haptics.light()
            leadingAction()
            offset = 0
            return
        }
        if total < -fullSwipe, let trailingAction {
            Haptics.light()
            trailingAction()
            offset = 0
            return
        }
        
        // Otherwise, snap open to reveal action or close
        if total > actionWidth / 2, leadingAction != nil {
            offset = actionWidth
        } else if total < -actionWidth / 2, trailingAction != nil {
            offset = -actionWidth
        } else {
            offset = 0
        }
    }
    
    private func triggerLeading() { leadingAction?() }
    private func triggerTrailing() { trailingAction?() }
}

private struct PriorityBadge: View {
    let priority: TaskPriority
    
    var body: some View {
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
