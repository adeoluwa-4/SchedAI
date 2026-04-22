//
//  SchedAI_Widget.swift
//  SchedAI-Widget
//
//  Created by Adeoluwa Adekoya on 4/17/26.
//

import WidgetKit
import SwiftUI
import AppIntents

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent())
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let now = Date()
        let entries = (0..<12).map { offset in
            let date = Calendar.current.date(byAdding: .hour, value: offset, to: now) ?? now
            return SimpleEntry(date: date, configuration: configuration)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
}

struct SchedAI_WidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Provider.Entry

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot.make(for: entry.date)
    }

    var body: some View {
        switch family {
        case .systemSmall:
            SmallSchedAIWidget(snapshot: snapshot)
        case .systemMedium:
            MediumSchedAIWidget(snapshot: snapshot)
        default:
            LargeSchedAIWidget(snapshot: snapshot)
        }
    }
}

struct SchedAI_Widget: Widget {
    let kind: String = "SchedAI_Widget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            SchedAI_WidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetWhiteBackground()
                }
        }
        .configurationDisplayName("SchedAI Plan")
        .description("See your real tasks and open voice planning quickly.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "😀"
        return intent
    }

    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "🤩"
        return intent
    }
}

private enum WidgetBridge {
    static let appGroupID = "group.me.SchedAI.shared"
    static let tasksKey = "widget_shared_tasks_v1"

    struct SharedTask: Codable, Identifiable {
        let id: UUID
        let title: String
        let priorityRaw: String?
        let estimatedMinutes: Int
        let isCompleted: Bool
        let scheduledStart: Date?
        let scheduledEnd: Date?
    }

    static func loadTasks() -> [SharedTask] {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return [] }
        guard let data = defaults.data(forKey: tasksKey) else { return [] }
        return (try? JSONDecoder().decode([SharedTask].self, from: data)) ?? []
    }
}

private extension WidgetBridge.SharedTask {
    var priorityLevel: WidgetTaskPriority {
        WidgetTaskPriority(rawValue: priorityRaw ?? "") ?? .medium
    }

    var resolvedEnd: Date? {
        if let scheduledEnd { return scheduledEnd }
        guard let start = scheduledStart else { return nil }
        return start.addingTimeInterval(TimeInterval(max(estimatedMinutes, 5) * 60))
    }

    var durationMinutes: Int {
        guard let start = scheduledStart, let end = resolvedEnd else {
            return max(estimatedMinutes, 5)
        }
        return max(Int(end.timeIntervalSince(start) / 60), 5)
    }

    var timeRangeLine: String {
        guard let start = scheduledStart, let end = resolvedEnd else { return "No time set" }
        if Calendar.current.isDate(start, inSameDayAs: Date()) {
            return "\(start.widgetTime) - \(end.widgetTime)"
        }
        return "\(start.widgetDayTime) - \(end.widgetTime)"
    }

    var startLine: String {
        guard let start = scheduledStart else { return "Anytime" }
        if Calendar.current.isDate(start, inSameDayAs: Date()) {
            return start.widgetTime
        }
        return start.widgetDayTime
    }

    var bracketStartLine: String {
        guard let start = scheduledStart else { return "[Anytime]" }
        return "[\(start.widgetBracketTime)]"
    }
}

private struct WidgetSnapshot {
    enum PlanMode {
        case scheduled
        case unscheduled
        case empty
    }

    let day: Date
    let allCount: Int
    let completedCount: Int
    let remainingCount: Int
    let planMode: PlanMode
    let nowTask: WidgetBridge.SharedTask?
    let nextTask: WidgetBridge.SharedTask?
    let planItems: [WidgetBridge.SharedTask]

    var progress: Double {
        guard allCount > 0 else { return 0 }
        return Double(completedCount) / Double(allCount)
    }

    var progressText: String {
        "\(Int(progress * 100))%"
    }

    var progressSubline: String {
        "\(completedCount) of \(max(allCount, 1)) done"
    }

    var primaryTask: WidgetBridge.SharedTask? {
        nowTask ?? nextTask ?? planItems.first
    }

    var planTitle: String {
        switch planMode {
        case .scheduled: return "TODAY'S PLAN"
        case .unscheduled: return "TODAY'S PLAN"
        case .empty: return "TODAY'S PLAN"
        }
    }

    var smallNextLine: String {
        if let nextTask, let start = nextTask.scheduledStart {
            return "Next: \(nextTask.title) at \(start.widgetHour)"
        }
        if let first = planItems.first {
            return "Next: \(first.title)"
        }
        return "Add tasks in SchedAI"
    }

    static func make(for date: Date) -> WidgetSnapshot {
        let allTasks = WidgetBridge.loadTasks()
        let remaining = allTasks.filter { !$0.isCompleted }
        let completedCount = allTasks.count - remaining.count
        let calendar = Calendar.current

        let scheduledRemaining = remaining
            .filter { $0.scheduledStart != nil }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }

        let scheduledToday = remaining
            .filter { task in
                guard let start = task.scheduledStart else { return false }
                return calendar.isDate(start, inSameDayAs: date)
            }
            .sorted { ($0.scheduledStart ?? .distantFuture) < ($1.scheduledStart ?? .distantFuture) }

        let nowTask = scheduledToday.first { task in
            guard let start = task.scheduledStart, let end = task.resolvedEnd else { return false }
            return date >= start && date < end
        }

        let nextTask = scheduledToday.first { task in
            guard let start = task.scheduledStart else { return false }
            return start > date
        }

        let unscheduled = remaining
            .filter { $0.scheduledStart == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let mode: PlanMode
        let items: [WidgetBridge.SharedTask]

        let combined = scheduledRemaining + unscheduled

        if !combined.isEmpty {
            mode = .scheduled
            items = combined
        } else {
            mode = .empty
            items = []
        }

        return WidgetSnapshot(
            day: date,
            allCount: allTasks.count,
            completedCount: completedCount,
            remainingCount: remaining.count,
            planMode: mode,
            nowTask: nowTask,
            nextTask: nextTask,
            planItems: items
        )
    }
}

private enum WidgetPalette {
    static let textPrimary = Color(red: 0.04, green: 0.06, blue: 0.1)
    static let textSecondary = Color(red: 0.13, green: 0.17, blue: 0.24)
    static let blue = Color(red: 0.14, green: 0.43, blue: 0.95)
    static let blueSoft = Color(red: 0.74, green: 0.84, blue: 0.98)
    static let panel = Color(red: 0.92, green: 0.95, blue: 0.99)
    static let card = Color.white.opacity(0.95)
}

private enum WidgetTaskPriority: String {
    case high
    case medium
    case low
}

private func bulletColor(for task: WidgetBridge.SharedTask) -> Color {
    switch task.priorityLevel {
    case .high:
        return Color(red: 0.93, green: 0.28, blue: 0.30)
    case .medium:
        return Color(red: 0.98, green: 0.77, blue: 0.22)
    case .low:
        return Color(red: 0.20, green: 0.78, blue: 0.39)
    }
}

private struct WidgetWhiteBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.95, green: 0.97, blue: 1.0),
                    Color(red: 0.91, green: 0.95, blue: 0.99)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            LinearGradient(
                colors: [
                    Color.clear,
                    Color(red: 0.46, green: 0.70, blue: 1.0).opacity(0.16),
                    Color(red: 0.32, green: 0.62, blue: 0.98).opacity(0.30)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            Circle()
                .fill(WidgetPalette.blue.opacity(0.08))
                .blur(radius: 42)
                .offset(x: 48, y: -36)
            Circle()
                .fill(Color.cyan.opacity(0.08))
                .blur(radius: 50)
                .offset(x: -60, y: 54)
        }
    }
}

private struct AppGlyph: View {
    let size: CGFloat

    var body: some View {
        Image("WidgetLogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .stroke(Color.white.opacity(0.55), lineWidth: 1)
            )
    }
}

private struct SmallSchedAIWidget: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                AppGlyph(size: 62)

                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetPalette.blue.opacity(0.72))
                    .offset(x: -52, y: -14)

                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(WidgetPalette.blue.opacity(0.72))
                    .offset(x: 52, y: -14)

                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WidgetPalette.blue.opacity(0.62))
                    .offset(x: 0, y: -38)
            }

            HStack(spacing: 0) {
                Text("Sched")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WidgetPalette.textPrimary)
                Text("AI")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WidgetPalette.blue)
            }

            MicPillButton(title: "Ask SchedAI", compact: true)

            Text(snapshot.smallNextLine)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(WidgetPalette.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(10)
    }
}

private struct MediumSchedAIWidget: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WidgetPalette.panel)
                .overlay(
                    VStack(spacing: 10) {
                        AppGlyph(size: 62)
                        MicCircleButton(size: 56)
                    }
                    .padding(.vertical, 10)
                    .padding(.leading, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                )
                .frame(width: 98)

            VStack(alignment: .leading, spacing: 7) {
                Text("NOW")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetPalette.blue)

                HStack(alignment: .top) {
                    Text(snapshot.primaryTask?.title ?? "No tasks")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.65)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(WidgetPalette.textPrimary)
                    Spacer(minLength: 4)
                    Image(systemName: "figure.run")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(WidgetPalette.blue)
                }

                HStack(spacing: 6) {
                    Text(snapshot.primaryTask?.timeRangeLine ?? "No time set")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(1)
                    if let primary = snapshot.primaryTask {
                        DurationPill(minutes: primary.durationMinutes)
                    }
                }

                Divider()
                    .overlay(Color.black.opacity(0.08))

                Text("UP NEXT")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WidgetPalette.blue)

                if !snapshot.planItems.isEmpty {
                    ForEach(Array(snapshot.planItems.prefix(2)), id: \.id) { task in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(bulletColor(for: task))
                                .frame(width: 7, height: 7)
                            Text(task.startLine)
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(WidgetPalette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                                .frame(width: 52, alignment: .leading)
                            Text(task.title)
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(WidgetPalette.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.7)
                                .allowsTightening(true)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 1)
                            DurationPill(minutes: task.durationMinutes, compact: true)
                        }
                    }
                } else {
                    Text("Add tasks in the app.")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }
}

private struct LargeSchedAIWidget: View {
    let snapshot: WidgetSnapshot

    private var focusTask: WidgetBridge.SharedTask? {
        snapshot.primaryTask
    }

    private var comingUpItems: [WidgetBridge.SharedTask] {
        let filtered = snapshot.planItems.filter { task in
            guard let focusTask else { return true }
            return task.id != focusTask.id
        }
        return Array(filtered.prefix(3))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                AppGlyph(size: 44)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        HStack(spacing: 0) {
                            Text("Sched")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(WidgetPalette.textPrimary)
                            Text("AI")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(WidgetPalette.blue)
                        }

                        Text("Today")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WidgetPalette.blue)
                    }

                    Text(snapshot.day.widgetDateLine)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(WidgetPalette.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 4)

                SparkleCircleButton(size: 36)
            }

            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 8) {
                    WhiteCard(fill: WidgetPalette.blueSoft.opacity(0.52)) {
                        HStack(alignment: .center, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("NOW")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(WidgetPalette.blue)
                                    .lineLimit(1)

                                Text(focusTask?.title ?? "No tasks")
                                    .font(.system(size: 23, weight: .bold, design: .rounded))
                                    .foregroundStyle(WidgetPalette.textPrimary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.62)

                                HStack(spacing: 6) {
                                    Text(focusTask?.timeRangeLine ?? "No time set")
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .foregroundStyle(WidgetPalette.textSecondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)

                                    if let focusTask {
                                        DurationPill(minutes: focusTask.durationMinutes, compact: true)
                                    }
                                }
                            }

                            Spacer(minLength: 4)

                            Image(systemName: "figure.run")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(WidgetPalette.blue)
                                .frame(width: 28)
                        }
                        .padding(10)
                    }
                    .frame(height: 88)

                    WhiteCard {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("COMING UP")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(WidgetPalette.blue)
                                .lineLimit(1)

                            if comingUpItems.isEmpty {
                                Text(snapshot.planItems.isEmpty ? "Add tasks in SchedAI." : "You're clear after this.")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WidgetPalette.textSecondary)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.75)
                            } else {
                                ForEach(comingUpItems, id: \.id) { task in
                                    LargeComingUpRow(task: task)
                                }
                            }
                        }
                        .padding(10)
                    }
                    .frame(height: 112)
                }

                VStack(spacing: 8) {
                    WhiteCard {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("PROGRESS")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(WidgetPalette.blue)
                                .lineLimit(1)

                            HStack {
                                Spacer(minLength: 0)
                                ProgressRing(progress: snapshot.progress, text: snapshot.progressText, subline: snapshot.progressSubline)
                                    .frame(width: 82, height: 82)
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(10)
                    }
                    .frame(height: 104)

                    WhiteCard {
                        HStack(alignment: .center, spacing: 6) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("REMAINING")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(WidgetPalette.blue)
                                    .lineLimit(1)

                                Text("\(snapshot.remainingCount)")
                                    .font(.system(size: 31, weight: .bold, design: .rounded))
                                    .foregroundStyle(WidgetPalette.textPrimary)
                                    .lineLimit(1)

                                Text("tasks")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(WidgetPalette.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "list.bullet")
                                .font(.system(size: 19, weight: .semibold))
                                .foregroundStyle(WidgetPalette.blue)
                                .frame(width: 32, height: 32)
                                .background(WidgetPalette.blueSoft.opacity(0.55), in: Circle())
                        }
                        .padding(10)
                    }
                    .frame(height: 96)
                }
                .frame(width: 128)
            }

            HStack(spacing: 8) {
                MicPillButton(title: "Ask SchedAI", compact: true)

                StaticActionPill(title: "Replan Today (\(snapshot.remainingCount))", systemName: "arrow.clockwise")
            }
            .frame(height: 38)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}

private struct LargeComingUpRow: View {
    let task: WidgetBridge.SharedTask

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Circle()
                .fill(bulletColor(for: task))
                .frame(width: 7, height: 7)

            Text(task.title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(WidgetPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 2)

            Text(task.timeRangeLine)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WidgetPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            DurationPill(minutes: task.durationMinutes, compact: true)
        }
        .frame(height: 21)
    }
}

private struct StaticActionPill: View {
    let title: String
    let systemName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .allowsTightening(true)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(WidgetPalette.blue)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(WidgetPalette.blueSoft.opacity(0.55), in: Capsule())
    }
}

private struct SparkleCircleButton: View {
    let size: CGFloat

    var body: some View {
        Button(intent: OpenVoicePlannerIntent()) {
            ZStack {
                Circle()
                    .fill(WidgetPalette.blueSoft.opacity(0.58))
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(WidgetPalette.blue)
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
    }
}

private struct WhiteCard<Content: View>: View {
    var fill: Color = WidgetPalette.card
    @ViewBuilder var content: Content

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .overlay(
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            )
    }
}

private struct MicPillButton: View {
    let title: String
    var compact: Bool = false

    var body: some View {
        Button(intent: OpenVoicePlannerIntent()) {
            HStack(spacing: 6) {
                Image(systemName: "mic.fill")
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .allowsTightening(true)
            }
            .font(.system(size: compact ? 12 : 16, weight: .semibold))
            .foregroundStyle(WidgetPalette.blue)
            .padding(.horizontal, compact ? 8 : 14)
            .padding(.vertical, compact ? 8 : 10)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.94))
                    .overlay(
                        Capsule()
                            .stroke(Color.black.opacity(0.1), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

private struct MicCircleButton: View {
    let size: CGFloat

    var body: some View {
        Button(intent: OpenVoicePlannerIntent()) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.23, green: 0.56, blue: 1.0), WidgetPalette.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
            )
            .shadow(color: WidgetPalette.blue.opacity(0.25), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }
}

private struct DurationPill: View {
    let minutes: Int
    var compact: Bool = false

    var body: some View {
        Text("\(minutes)m")
            .font(.system(size: compact ? 9 : 11, weight: .bold))
            .foregroundStyle(WidgetPalette.blue)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 1 : 2)
            .background(WidgetPalette.blueSoft.opacity(0.65), in: Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ProgressRing: View {
    let progress: Double
    let text: String
    let subline: String

    var body: some View {
        ZStack {
            Circle()
                .stroke(WidgetPalette.blue.opacity(0.2), lineWidth: 10)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [Color(red: 0.44, green: 0.72, blue: 1.0), WidgetPalette.blue]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 1) {
                Text(text)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(WidgetPalette.textPrimary)
                Text(subline)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.textSecondary)
                    .lineLimit(1)
            }
        }
    }
}

private extension Date {
    var widgetTime: String {
        formatted(date: .omitted, time: .shortened)
    }

    var widgetDayTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E h:mm a"
        return formatter.string(from: self)
    }

    var widgetHour: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: self)
    }

    var widgetDateLine: String {
        formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var widgetBracketTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: self)
    }
}

#Preview(as: .systemSmall) {
    SchedAI_Widget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley)
}

#Preview(as: .systemMedium) {
    SchedAI_Widget()
} timeline: {
    SimpleEntry(date: .now, configuration: .starEyes)
}

#Preview(as: .systemLarge) {
    SchedAI_Widget()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley)
}
