import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Syllabus → semester plan, in three steps:
/// 1. Choose: PDF, photo, or pasted text.
/// 2. Review: course name, class times, and every deadline found (editable).
/// 3. Plan: saves deadlines and classes, creates spaced study sessions.
struct SyllabusImportSheet: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var semester: SemesterStore
    @Environment(\.dismiss) private var dismiss

    var onFinish: (String) -> Void = { _ in }

    private enum Step { case choose, reading, review }

    private struct DraftDeadline: Identifiable {
        var id = UUID()
        var include = true
        var deadline: CourseDeadline
    }

    private struct DraftClass: Identifiable {
        var id = UUID()
        var include = true
        var meeting: ClassMeeting
    }

    @State private var step: Step = .choose
    @State private var pastedText = ""
    @State private var showPaste = false
    @State private var showFileImporter = false
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?

    @State private var course = ""
    @State private var drafts: [DraftDeadline] = []
    @State private var classDrafts: [DraftClass] = []

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .choose: chooseView
                case .reading: readingView
                case .review: reviewView
                }
            }
            .navigationTitle(step == .review ? "Review" : "Add syllabus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.pdf, .plainText, .text]) { result in
            switch result {
            case .success(let url): read { try readFile(url) }
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            readPhoto(item)
        }
        .alert("Couldn't read that", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        #if DEBUG
        .task {
            if DebugFixtures.has("-SchedAIOpenSyllabus"), drafts.isEmpty {
                apply(SyllabusReader.read(DebugFixtures.sampleSyllabus))
            }
        }
        #endif
    }

    // MARK: Step 1: choose

    private var chooseView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("SchedAI reads it on your iPhone and finds every exam, quiz, paper and assignment, plus your class times. You'll review everything before anything is saved.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                sourceButton("PDF from Files", detail: "The syllabus your professor posted", icon: "doc.fill") {
                    showFileImporter = true
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    sourceRow("Photo or screenshot", detail: "A printed schedule or a screenshot of Canvas", icon: "photo.fill")
                }
                .buttonStyle(.plain)
                sourceButton("Paste text", detail: "Copy the schedule section and paste it", icon: "doc.on.clipboard.fill") {
                    withAnimation { showPaste.toggle() }
                }

                if showPaste {
                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $pastedText)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
                        Button {
                            let text = pastedText
                            read { text }
                        } label: {
                            Text("Read syllabus").font(.headline).frame(maxWidth: .infinity).frame(height: 48)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: 14))
                        .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Label("Nothing leaves your iPhone.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(20)
        }
    }

    private func sourceButton(_ title: String, detail: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { sourceRow(title, detail: detail, icon: icon) }.buttonStyle(.plain)
    }

    private func sourceRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .contentShape(Rectangle())
    }

    // MARK: Step 2: reading

    private var readingView: some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text("Reading your syllabus…").font(.headline)
            Text("Finding exams, deadlines and class times").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Step 3: review

    private var includedDeadlines: [CourseDeadline] {
        drafts.filter(\.include).map { d in var x = d.deadline; x.course = courseName; return x }
    }

    private var courseName: String {
        let trimmed = course.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Course" : trimmed
    }

    private var plannedSessionCount: Int {
        includedDeadlines.reduce(0) { $0 + StudyPlanner.sessions(for: $1).count }
    }

    private var reviewView: some View {
        List {
            Section {
                TextField("Course name, e.g. CHEM 101", text: $course)
                    .font(.title3.weight(.semibold))
                    .textInputAutocapitalization(.characters)
            } header: {
                Text("Course")
            }

            if !classDrafts.isEmpty {
                Section {
                    ForEach($classDrafts) { $draft in
                        Toggle(isOn: $draft.include) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(draft.meeting.weekdaySummary).font(.body.weight(.semibold))
                                Text(draft.meeting.timeSummary).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Class times found")
                } footer: {
                    Text("Study sessions are never planned during class.")
                }
            }

            Section {
                if drafts.isEmpty {
                    Text("No deadlines found. Try pasting just the schedule section, or add them later.")
                        .foregroundStyle(.secondary)
                }
                ForEach($drafts) { $draft in
                    DraftDeadlineRow(include: $draft.include, deadline: $draft.deadline)
                }
                .onDelete { drafts.remove(atOffsets: $0) }
            } header: {
                Text("\(drafts.count) deadline\(drafts.count == 1 ? "" : "s") found")
            } footer: {
                Text("Check the dates: syllabi are messy. Swipe left to remove anything that isn't a real deadline.")
            }

            Section {
                Button {
                    save()
                } label: {
                    VStack(spacing: 2) {
                        Text("Plan my semester").font(.headline)
                        Text("\(includedDeadlines.count) deadlines · \(plannedSessionCount) study sessions")
                            .font(.caption)
                            .opacity(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 14))
                .disabled(includedDeadlines.isEmpty && !classDrafts.contains(where: \.include))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Button("Use a different syllabus") { withAnimation { step = .choose } }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
    }

    // MARK: Actions

    private func readFile(_ url: URL) throws -> String {
        if url.pathExtension.lowercased() == "pdf" { return try SyllabusReader.text(fromPDF: url) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func readPhoto(_ item: PhotosPickerItem) {
        withAnimation { step = .reading }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { throw SyllabusReader.ExtractionError.unreadableImage }
                let text = try await SyllabusReader.text(fromImage: image)
                await MainActor.run { apply(SyllabusReader.read(text)) }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    withAnimation { step = .choose }
                }
            }
            await MainActor.run { photoItem = nil }
        }
    }

    private func read(_ produceText: @escaping () throws -> String) {
        withAnimation { step = .reading }
        Task {
            do {
                let text = try produceText()
                let result = SyllabusReader.read(text)
                await MainActor.run { apply(result) }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    withAnimation { step = .choose }
                }
            }
        }
    }

    private func apply(_ result: SyllabusReader.Result) {
        course = result.course ?? course
        drafts = result.deadlines.map { DraftDeadline(deadline: $0) }
        classDrafts = result.classes.map { DraftClass(meeting: $0) }
        withAnimation { step = .review }
    }

    private func save() {
        let deadlines = includedDeadlines
        let classes = classDrafts.filter(\.include).map { d in var m = d.meeting; m.course = courseName; return m }
        semester.add(deadlines: deadlines, classes: classes)
        let sessions = app.addStudySessions(for: deadlines)
        app.planUnscheduledOnly(for: Date())
        Haptics.medium()
        onFinish("Planned \(sessions) study session\(sessions == 1 ? "" : "s") for \(courseName).")
        dismiss()
    }
}

/// Editable row in the review list.
private struct DraftDeadlineRow: View {
    @Binding var include: Bool
    @Binding var deadline: CourseDeadline

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button { include.toggle() } label: {
                Image(systemName: include ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(include ? Color.accentColor : Color(uiColor: .tertiaryLabel))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(include ? "Included" : "Excluded")

            VStack(alignment: .leading, spacing: 6) {
                TextField("Title", text: $deadline.title)
                    .font(.body.weight(.semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { kindMenu; datePicker }
                    VStack(alignment: .leading, spacing: 6) { kindMenu; datePicker }
                }
            }
            .opacity(include ? 1 : 0.45)
        }
        .padding(.vertical, 4)
    }

    private var kindMenu: some View {
        Picker("Type", selection: $deadline.kind) {
            ForEach(DeadlineKind.allCases) { kind in
                Label(kind.displayName, systemImage: kind.systemImage).tag(kind)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }

    private var datePicker: some View {
        DatePicker("Due", selection: $deadline.due, displayedComponents: deadline.hasTime ? [.date, .hourAndMinute] : [.date])
            .labelsHidden()
            .fixedSize()
    }
}
