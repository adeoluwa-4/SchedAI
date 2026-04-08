import SwiftUI

struct ReminderLeadTimePicker: View {
    @Binding var selected: Int
    @Environment(\.dismiss) private var dismiss

    private let presets: [Int] = [1, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120]

    var body: some View {
        Form {
            Section("Quick Choices") {
                ForEach(presets, id: \.self) { m in
                    Button {
                        Haptics.medium()
                        selected = m
                        dismiss()
                    } label: {
                        HStack {
                            Text(label(for: m))
                            Spacer()
                            if selected == m {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Custom") {
                Stepper(value: $selected, in: 1...180, step: 1) {
                    HStack {
                        Text("Minutes before")
                        Spacer()
                        Text("\(selected) min")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Lead Time")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func label(for minutes: Int) -> String {
        if minutes == 1 { return "1 minute before" }
        if minutes % 60 == 0 { return "\(minutes / 60) hour\(minutes >= 120 ? "s" : "") before" }
        return "\(minutes) minutes before"
    }
}

#Preview {
    NavigationStack {
        ReminderLeadTimePicker(selected: .constant(15))
    }
}
