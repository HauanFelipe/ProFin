import SwiftUI
import SwiftData

struct ReportsView: View {
    @Query(sort: \FinancialTransaction.date, order: .reverse)
    private var transactions: [FinancialTransaction]
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

    private var monthlyTransactions: [FinancialTransaction] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: selectedMonth) else { return [] }
        return transactions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button("Mês anterior", systemImage: "chevron.left") { moveMonth(by: -1) }
                            .labelStyle(.iconOnly)
                        Spacer()
                        Text(selectedMonth, format: .dateTime.month(.wide).year())
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.updatesFrequently)
                        Spacer()
                        Button("Próximo mês", systemImage: "chevron.right") { moveMonth(by: 1) }
                            .labelStyle(.iconOnly)
                            .disabled(Calendar.current.isDate(selectedMonth, equalTo: Date(), toGranularity: .month))
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 4)
                }

                MonthlySummarySection(transactions: transactions, month: selectedMonth)

                Section("Movimentações do mês") {
                    if monthlyTransactions.isEmpty {
                        Text("Nenhuma receita ou despesa registrada neste mês.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(monthlyTransactions) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Relatórios")
        }
    }

    private func moveMonth(by offset: Int) {
        if let month = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = month
        }
    }
}
