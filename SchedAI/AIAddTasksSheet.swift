import SwiftUI
import Foundation

/// Paste/type multiple tasks (one per line or separated by semicolons),
/// preview them, then add to AppState.
struct AIAddTasksSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    @State private var input: String = ""
    @State private var isParsing: Bool = false
    @State private var parsedPreview: [TaskItem] = []

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                TextEditor(text: $input)
                    .frame(minHeight: 160)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.thinMaterial))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(.quaternary, lineWidth: 1))
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                HStack(spacing: 12) {
                    Button {
                        parsePreview()
                    } label: {
                        Label(isParsing ? "Parsing…" : "Preview", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isParsing)

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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func parsePreview() {
        isParsing = true
        let parsed = OfflineNLP.parseSafely(input)
        parsedPreview = parsed
        isParsing = false
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
