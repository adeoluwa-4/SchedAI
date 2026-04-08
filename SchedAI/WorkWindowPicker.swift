import SwiftUI

struct WorkWindowPicker: View {
    @Binding var start: Date
    @Binding var end: Date
    @Environment(\.dismiss) private var dismiss
    
    private var isInvalidRange: Bool {
        end <= start
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Work Window")) {
                    DatePicker("Start", selection: $start, displayedComponents: [.hourAndMinute])
                    DatePicker("End", selection: $end, displayedComponents: [.hourAndMinute])
                }
                
                if isInvalidRange {
                    Section {
                        Label("End time must be after start time", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Work Window")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                   
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // Auto-correct if invalid: set end to 1 hour after start
                        if end <= start {
                            end = Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    @State var start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
    @State var end = Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date())!
    return WorkWindowPicker(start: $start, end: $end)
}
