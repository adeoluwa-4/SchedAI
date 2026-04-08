import SwiftUI
import Combine
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

// Generic action button used in TodayView actions section
struct ActionButton: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemName)
                Text(title)
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

// "Now" card variants: either show current task or a free-until message
struct NowCardView: View {
    var task: TaskItem?
    var freeUntil: Date?
    var onComplete: (() -> Void)?

    init(task: TaskItem, onComplete: (() -> Void)? = nil) {
        self.task = task
        self.freeUntil = nil
        self.onComplete = onComplete
    }

    init(freeUntil: Date) {
        self.task = nil
        self.freeUntil = freeUntil
        self.onComplete = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let task {
                HStack {
                    Text("Now")
                        .font(.headline)
                    Spacer()
                    if let onComplete {
                        Button {
                            onComplete()
                        } label: {
                            Label("Complete", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                Text(task.title)
                    .font(.title3).fontWeight(.semibold)
                    .lineLimit(2)
            } else if let freeUntil {
                Text("Free until \(freeUntil.formatted(date: .omitted, time: .shortened))")
                    .font(.headline)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
    }
}

// Next up list card showing a small list of tasks
struct NextUpCardView: View {
    let tasks: [TaskItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next up")
                .font(.headline)
            ForEach(tasks) { t in
                HStack(spacing: 8) {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                    Text(t.title)
                        .lineLimit(1)
                        .font(.subheadline)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 5)
    }
}

// Simple quick-add sheet that returns text via onSubmit closure
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text: String = ""
    let onSubmit: (String) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("List your tasks (one per line or commas)", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                Text("Tip: separate tasks with commas or new lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                HStack {
                    Button("Cancel") { dismiss() }
                    Spacer()
                    Button("Add & Plan") {
                        onSubmit(text)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal)
                Spacer()
            }
            .padding(.top)
            .navigationTitle("Quick Plan")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add & Plan") {
                        onSubmit(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
