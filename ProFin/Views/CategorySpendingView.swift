import SwiftUI
import SwiftData

struct CategorySpendingView: View {
    let categoryID: UUID
    let month: Date
    @Query private var refunds: [CardRefund]
    @Query private var categories: [Category]
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @Query(sort: \CardInstallment.number) private var installments: [CardInstallment]

    private var name: String { categories.first { $0.id == categoryID }?.name ?? "Categoria" }
    private var expenses: [FinancialTransaction] {
        transactions.filter {
            $0.type == .expense && $0.category.id == categoryID
                && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }
    private var monthlyInstallments: [CardInstallment] {
        installments.filter {
            $0.purchase.category.id == categoryID && $0.purchase.date <= Date()
                && Calendar.current.isDate($0.invoice.referenceMonth, equalTo: month, toGranularity: .month)
        }
    }

    private var monthlyRefunds: [CardRefund] {
        refunds.filter { $0.purchase.category.id == categoryID && $0.date <= Date()
            && Calendar.current.isDate($0.invoice.referenceMonth, equalTo: month, toGranularity: .month) }
    }
    var body: some View {
        List {
            Section {
                Text(month, format: .dateTime.month(.wide).year()).font(.headline)
                switch Result(catching: { try SpendingAnalysis.calculate(
                    transactions: expenses, installments: monthlyInstallments, month: month, refunds: refunds.filter { $0.purchase.category.id == categoryID }
                ) }) {
                case .success(let result):
                    Text("Saldo de gastos com \(name), após estornos: \(Money.formatted(result.total)).")
                        .font(.title3.bold())
                    Text("\(expenses.count + monthlyInstallments.count) lançamentos nesta categoria.")
                        .foregroundStyle(.secondary)
                case .failure:
                    Text("Não foi possível calcular o total desta categoria.")
                }
            }
            if expenses.isEmpty && monthlyInstallments.isEmpty && monthlyRefunds.isEmpty {
                Text("Nenhum gasto registrado nesta categoria no mês selecionado.")
                    .foregroundStyle(.secondary)
            }
            if !expenses.isEmpty {
                Section("Despesas nas contas") {
                    ForEach(expenses) { transaction in
                        NavigationLink { TransactionDetailView(transaction: transaction) } label: {
                            TransactionRow(transaction: transaction)
                        }
                    }
                }
            }
            if !monthlyInstallments.isEmpty {
                Section("Parcelas do cartão") {
                    ForEach(monthlyInstallments) { installment in
                        NavigationLink { CardPurchaseDetailView(purchaseID: installment.purchase.id) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(installment.purchase.title).font(.headline)
                                Text(Money.formatted(installment.amountInCents))
                                Text("\(installment.purchase.card.name) · Parcela \(installment.number)/\(installment.purchase.installments.count)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(installment.invoice.dueDate, format: .dateTime.day().month(.wide).year())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !monthlyRefunds.isEmpty {
                Section("Estornos no mês") {
                    ForEach(monthlyRefunds) { refund in
                        NavigationLink { CardPurchaseDetailView(purchaseID: refund.purchase.id) } label: {
                            LabeledContent(refund.purchase.title, value: "− " + Money.formatted(refund.amountInCents))
                        }
                    }
                }
            }
            Section {
                Text("Estornos reduzem o total no mês do crédito; um total negativo indica crédito. O total usa a categoria escolhida por você. Inclui despesas e parcelas das faturas do mês, sem somar novamente o pagamento da fatura. Transferências para caixinhas não entram como gastos.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(name)
        .proFinScreen()
        .navigationBarTitleDisplayMode(.inline)
    }
}
