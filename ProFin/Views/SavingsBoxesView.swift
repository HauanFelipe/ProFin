import SwiftUI
import SwiftData

struct SavingsBoxesView: View {
    @Query(sort: \FinancialAccount.name) private var accounts: [FinancialAccount]
    @State private var showingNewBox = false
    @State private var showingTransfer = false

    private var savingsBoxes: [FinancialAccount] {
        accounts.filter { $0.isActive && $0.kind == .savingsBox }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Total em caixinhas") {
                    switch Result(catching: { try FinancialSummary.netWorth(accounts: savingsBoxes) }) {
                    case .success(let amount?):
                        ProFinBalanceCard(title: "Você já guardou", value: Money.formatted(amount),
                            explanation: "Soma das suas caixinhas ativas.", symbol: "archivebox.fill")
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    case .success(nil):
                        Text("Informe quanto dinheiro há em cada caixinha ativa para calcular o total.")
                            .foregroundStyle(.secondary)
                    case .failure:
                        Text("Não foi possível calcular o total.").foregroundStyle(.secondary)
                    }
                }
                Section("Caixinhas ativas") {
                    if savingsBoxes.isEmpty {
                        Text("Crie uma caixinha para acompanhar seu saldo e suas transferências.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(savingsBoxes) { account in
                        NavigationLink {
                            AccountDetailView(accountID: account.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(account.name, systemImage: "archivebox")
                                AccountBalanceText(account: account).font(.subheadline)
                            }
                        }
                    }
                    Button("Criar caixinha", systemImage: "plus") { showingNewBox = true }
                }
                Section {
                    Button { showingTransfer = true } label: {
                        ProFinFeatureLabel(title: "Guardar ou retirar dinheiro", subtitle: "Transfira entre suas contas e caixinhas", symbol: "arrow.left.arrow.right")
                    }
                    NavigationLink("Gerenciar contas", destination: AccountsView())
                } footer: {
                    Text("Transferências movimentam seu patrimônio sem alterar receitas ou despesas. Em Gerenciar contas, cadastre a conta corrente e informe quanto dinheiro há em cada conta.")
                }
            }
            .navigationTitle("Caixinhas")
            .proFinScreen()
            .sheet(isPresented: $showingNewBox) { AccountFormView(defaultKind: .savingsBox) }
            .sheet(isPresented: $showingTransfer) { TransferFormView() }
        }
    }
}
