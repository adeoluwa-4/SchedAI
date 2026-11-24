import SwiftUI

/// "You're behind" card with a one-tap fix. Shown on Today and Semester.
struct StudyCoachCard: View {
    @EnvironmentObject private var app: AppState
    @EnvironmentObject private var semester: SemesterStore
    var onResult: (String) -> Void = { _ in }

    private var behind: [StudyPlanner.Progress] {
        app.studyBehind(deadlines: semester.deadlines)
    }

    var body: some View {
        if let worst = behind.first {
            let missed = behind.reduce(0) { $0 + $1.behind }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.arrow.triangle.2.circlepath")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline(worst: worst, missed: missed))
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detail(worst: worst, others: behind.count - 1))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button {
                    Haptics.medium()
                    let result = withAnimation(.snappy) { app.catchUpOnStudy(deadlines: semester.deadlines) }
                    onResult(message(for: result))
                } label: {
                    Label("Fix my week", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .buttonBorderShape(.roundedRectangle(radius: 12))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.orange.opacity(0.12))
            )
        }
    }

    private func headline(worst: StudyPlanner.Progress, missed: Int) -> String {
        "You're \(missed) study session\(missed == 1 ? "" : "s") behind"
    }

    private func detail(worst: StudyPlanner.Progress, others: Int) -> String {
        let when: String
        switch worst.daysLeft {
        case 0: when = "today"
        case 1: when = "tomorrow"
        default: when = "in \(worst.daysLeft) days"
        }
        var text = "\(worst.deadline.displayTitle) is \(when)."
        if others > 0 { text += " \(others) other deadline\(others == 1 ? " is" : "s are") affected too." }
        return text + " SchedAI can spread what you missed across the lighter days before then."
    }

    private func message(for result: StudyPlanner.CatchUpResult) -> String {
        if result.moved == 0 { return "Nothing to move. You're on track." }
        var text = "Moved \(result.moved) session\(result.moved == 1 ? "" : "s") onto lighter days."
        if result.tooLate > 0 { text += " \(result.tooLate) were past their deadline." }
        return text
    }
}
