import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("SchedAI")
                    .font(.largeTitle)
                    .bold()
                Text("Welcome")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }
}

#Preview {
    HomeView()
}
