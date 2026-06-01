import SwiftUI
#if os(iOS)
import UIKit
#endif

// Lightweight haptics helper used in TodayView
enum Haptics {
    static func light() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
    static func medium() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        #endif
    }
}

struct PlanStateBadge: View {
    let state: TaskPlanDisplayState

    var body: some View {
        Label(state.displayName, systemImage: state.systemImage)
            .font(.caption2.weight(.bold))
            .foregroundStyle(state.tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(state.tint.opacity(0.14))
            )
            .accessibilityLabel("Plan state: \(state.displayName)")
    }
}

private extension TaskPlanDisplayState {
    var tint: Color {
        switch self {
        case .unplanned: return .secondary
        case .planned: return .blue
        case .pinned: return .purple
        case .later: return .orange
        case .skippedToday: return .gray
        case .blocked: return .red
        case .done: return .green
        }
    }
}
