import SwiftUI

struct AIPlanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppState

    @StateObject private var speech = SpeechRecognizer()
    @State private var transcript: String = ""
    @State private var isAuthorized = false
    @State private var parsedPreview: [TaskItem] = []
    @State private var isPlanning = false
    @State private var animateLoader = false

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
                            parsedPreview = []
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

                            ForEach(parsedPreview) { task in
                                HStack {
                                    Text(task.title)
                                        .font(.body)
                                    Spacer()
                                    if let start = task.scheduledStart {
                                        Text(time(start))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
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
                self.parsedPreview = []
            }
        }
    }

    // MARK: - Actions

    private func setupPermissions() async {
        let ok = await speech.ensureAuthorized()
        await MainActor.run { isAuthorized = ok }
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
        if items.isEmpty {
            parsedPreview = [
                TaskItem(title: text, estimatedMinutes: 30, priority: .medium)
            ]
        } else {
            parsedPreview = items
        }
    }

    private func confirmPlan() {
        guard !parsedPreview.isEmpty else { return }
        isPlanning = true
        animateLoader = true

        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            await MainActor.run {
                parsedPreview.forEach { app.addTask($0) }
                app.planToday(for: app.planningDate)
                dismiss()
            }
        }
    }

    private func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
