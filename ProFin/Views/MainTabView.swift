import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Início", systemImage: "house.fill") {
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
        .toolbarBackground(ProFinStyle.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
    }
}
