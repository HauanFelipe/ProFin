import SwiftUI

struct GoalsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Seus próximos objetivos",
                systemImage: "target",
                description: Text("Esta é a área das suas metas financeiras. Em breve, você poderá cadastrar objetivos e acompanhar seu progresso.")
            )
            .navigationTitle("Metas")
        }
    }
}
