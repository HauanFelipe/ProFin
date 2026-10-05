import SwiftUI
import SwiftData

struct CardCommitmentsView: View {
    var cardID: UUID?
    @Query private var invoices: [CardInvoice]
    private var future: [CardInvoice] {
        let start = Calendar.current.dateInterval(of: .month, for: Date())!.end
        return invoices.filter {
            (cardID == nil || $0.card.id == cardID) && $0.referenceMonth >= start
                && (!$0.installments.isEmpty || !$0.refunds.isEmpty)
        }.sorted { $0.referenceMonth == $1.referenceMonth ? $0.card.name < $1.card.name : $0.referenceMonth < $1.referenceMonth }
    }
    var body: some View {
        List {
            Section {
                Text("Valores das compras e estornos já registrados. Não inclui novas compras, juros, tarifas ou futuras assinaturas ainda não lançadas. Créditos de faturas anteriores já são abatidos do valor pendente.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if future.isEmpty { Text("Nenhuma parcela ou crédito registrado para os próximos meses.") }
            ForEach(Array(Set(future.map(\.referenceMonth))).sorted(), id: \.self) { month in
                let items = future.filter { $0.referenceMonth == month }
                Section {
                    if let total = try? CreditCardService.debt(items) {
                        LabeledContent("Ainda a pagar", value: Money.formatted(total)).fontWeight(.semibold)
                    } else { Text("Total indisponível") }
                    ForEach(items) { invoice in
                        NavigationLink { CardInvoiceView(invoiceID: invoice.id) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(invoice.card.name).font(.headline)
                                Text("\(invoice.installments.count) parcelas · \(CreditCardService.status(invoice))")
                                Text("Pendente: \((try? CreditCardService.pending(invoice)).map(Money.formatted) ?? "Indisponível")")
                                Text(invoice.dueDate, format: .dateTime.day().month().year()).font(.caption)
                            }
                        }
                    }
                } header: { Text(month, format: .dateTime.month(.wide).year()) }
            }
        }
        .navigationTitle("Próximos meses")
        .proFinScreen()
    }
}
