import SwiftUI
import SwiftData

struct AccountsView: View {
    @Query(sort: \FinancialAccount.name) private var accounts: [FinancialAccount]
    @State private var showingNewAccount = false

    var body: some View {
        List {
            ForEach(accounts) { account in
                NavigationLink {
                    AccountDetailView(accountID: account.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(account.name).font(.headline)
                        Text("\(account.kind.title)\(account.isActive ? "" : " · Inativa")")
                            .font(.caption).foregroundStyle(.secondary)
                        AccountBalanceText(account: account).font(.subheadline)
                    }
                }
            }
            Section {
                Text("O patrimônio total soma os saldos das contas ativas. Contas inativas mantêm o histórico e podem ser reativadas.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Contas")
        .proFinScreen()
        .toolbar {
            Button("Nova conta", systemImage: "plus") { showingNewAccount = true }
        }
        .sheet(isPresented: $showingNewAccount) { AccountFormView() }
    }
}
