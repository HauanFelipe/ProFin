import SwiftUI

struct TransactionDetailView: View {
    let transaction: FinancialTransaction

    var body: some View {
        Form {
            Section("Movimentação") {
                LabeledContent("Descrição", value: transaction.title)
                LabeledContent("Tipo", value: transaction.type.title)
                LabeledContent("Valor", value: Money.formatted(transaction.amountInCents))
                LabeledContent("Data") {
                    Text(transaction.date, format: .dateTime.day().month(.wide).year())
                }
                LabeledContent("Categoria", value: transaction.category.name)
                LabeledContent("Conta", value: transaction.account?.name ?? "Não definida")

                if transaction.type == .expense, let classification = transaction.classification {
                    LabeledContent("Classificação", value: classification.title)
                }
            }

            if let notes = transaction.notes, !notes.isEmpty {
                Section("Observação") {
                    Text(notes)
                }
            }

            if let occurrence = transaction.recurringOccurrence {
                Section("Pagamento de conta recorrente") {
                    Text(occurrence.title)
                    LabeledContent("Mês da cobrança") {
                        Text(occurrence.referenceMonth, format: .dateTime.month(.wide).year())
                    }
                    Text("Esta movimentação é o pagamento da cobrança. O valor entra nas despesas apenas uma vez.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Detalhes")
        .navigationBarTitleDisplayMode(.inline)
    }
}
