import SwiftUI

struct MonthlySummarySection: View {
    let transactions: [FinancialTransaction]
    let month: Date

    var body: some View {
        Section {
            if let summary = try? FinancialSummary.monthlySummary(
                transactions: transactions, monthContaining: month
            ) {
                LabeledContent("Receitas") {
                    Text(Money.formatted(summary.incomeInCents))
                        .foregroundStyle(.green)
                }
                LabeledContent("Despesas") {
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
            Text("Transferências entre contas não alteram as receitas, as despesas ou o resultado do mês.")
        }
    }
}
