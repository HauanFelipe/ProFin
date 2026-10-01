import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Dashboard", systemImage: "square.grid.2x2") {
                DashboardView()
            }

            Tab("Movimentações", systemImage: "arrow.left.arrow.right") {
                TransactionListView()
            }

            Tab("Caixinhas", systemImage: "archivebox") {
                SavingsBoxesView()
            }

            Tab("Metas", systemImage: "target") {
                GoalsView()
            }

            Tab("Relatórios", systemImage: "chart.bar.xaxis") {
                ReportsView()
            }
        }
    }
}
