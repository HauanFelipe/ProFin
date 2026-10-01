import SwiftUI
import SwiftData

struct DashboardView: View {
    @Query(sort: \FinancialAccount.name)
    private var accounts: [FinancialAccount]
    @Query(sort: \FinancialTransaction.date, order: .reverse)
    private var transactions: [FinancialTransaction]
    @State private var referenceDate = Date()

    var body: some View {
        NavigationStack {
            List {
                Section("Patrimônio total") {
                    switch Result(catching: { try FinancialSummary.netWorth(accounts: accounts, asOf: referenceDate) }) {
                    case .success(let amount?):
                        Text(Money.formatted(amount))
                            .font(.title.bold())
                            .contentTransition(.numericText())
                    case .success(nil):
                        Label("Patrimônio incompleto", systemImage: "info.circle")
                            .font(.headline)
                        Text("Há contas com saldo inicial ainda não informado. O patrimônio será calculado quando todos os saldos iniciais estiverem definidos.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    case .failure:
                        Label("Não foi possível calcular o patrimônio.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                MonthlySummarySection(transactions: transactions, month: referenceDate)

                Section("Últimas movimentações") {
                    if transactions.isEmpty {
                        Text("Registre sua primeira receita ou despesa na aba Movimentações.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(transactions.prefix(5)) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Dashboard")
            .onAppear { referenceDate = Date() }
        }
    }
}
