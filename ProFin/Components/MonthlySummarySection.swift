import SwiftUI
import SwiftData

struct MonthlySummarySection: View {
    let transactions: [FinancialTransaction]
    let month: Date
    @Query private var refunds: [CardRefund]
    @Query private var installments: [CardInstallment]

    var body: some View {
        Section {
            if let summary = try? FinancialSummary.monthlySummary(
                transactions: transactions, monthContaining: month, installments: installments, refunds: refunds
            ) {
                LabeledContent("Receitas") {
                    Text(Money.formatted(summary.incomeInCents))
                        .foregroundStyle(.green)
                }
                LabeledContent("Gastos do mês") {
                    Text(Money.formatted(summary.expenseInCents))
                        .foregroundStyle(.red)
                }
                LabeledContent("Resultado do mês") {
                    Text(Money.formatted(summary.resultInCents))
                        .fontWeight(.semibold)
                        .foregroundStyle(summary.resultInCents < 0 ? Color.red : Color.primary)
                }
            } else {
                Label("Não foi possível calcular os totais deste mês.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(month, format: .dateTime.month(.wide).year())
        } footer: {
            Text("Gastos incluem despesas das contas e parcelas das faturas deste mês, menos os estornos creditados nessas faturas. Um valor negativo indica crédito líquido. Pagamentos de fatura e transferências não são contados novamente. Esse resultado não representa apenas saídas de caixa.")
        }
    }
}
