import SwiftUI
import SwiftData

struct ReportsView: View {
    @Query private var refunds: [CardRefund]
    @Query(sort: \FinancialTransaction.date, order: .reverse)
    private var transactions: [FinancialTransaction]
    @Query private var installments: [CardInstallment]
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()

    private var monthlyTransactions: [FinancialTransaction] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: selectedMonth) else { return [] }
        return transactions.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProFinIntro(title: "Entenda seus gastos", message: "Escolha o mês e toque em uma categoria para ver os detalhes.", symbol: "chart.bar.fill")
                }
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

                switch Result(catching: { try SpendingAnalysis.calculate(
                    transactions: transactions, installments: installments, month: selectedMonth, refunds: refunds
                ) }) {
                case .success(let analysis):
                    SpendingAnalysisSections(analysis: analysis, month: selectedMonth)
                case .failure:
                    Section { Text("Não foi possível calcular a análise de gastos. Confira os valores cadastrados.") }
                }

                Section("Parcelas das faturas do mês") {
                    ForEach(installments.filter { Calendar.current.isDate($0.invoice.referenceMonth, equalTo: selectedMonth, toGranularity: .month) }) { item in
                        NavigationLink { CardPurchaseDetailView(purchaseID: item.purchase.id) } label: {
                            VStack(alignment: .leading) {
                                Text("\(item.purchase.title) · \(item.number)/\(item.purchase.installments.count)")
                                Text("\(item.purchase.category.name) · \(Money.formatted(item.amountInCents))").font(.subheadline)
                            }
                        }
                    }
                }
                Section("Estornos das faturas do mês") {
                    ForEach(refunds.filter { $0.date <= Date() && Calendar.current.isDate($0.invoice.referenceMonth, equalTo: selectedMonth, toGranularity: .month) }) { refund in
                        NavigationLink { CardPurchaseDetailView(purchaseID: refund.purchase.id) } label: {
                            LabeledContent(refund.purchase.title, value: "− " + Money.formatted(refund.amountInCents))
                        }
                    }
                }
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
            .proFinScreen()
        }
    }

    private func moveMonth(by offset: Int) {
        if let month = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = month
        }
    }
}
