import SwiftUI
import SwiftData

struct CreditCardsView: View {
    @Query(sort: \CreditCard.name) private var cards: [CreditCard]
    @State private var adding = false
    var body: some View {
        List {
            NavigationLink("Parcelas dos próximos meses") { CardCommitmentsView() }
            if cards.isEmpty { Text("Cadastre seu cartão para registrar compras e parcelas.").foregroundStyle(.secondary) }
            ForEach(cards) { card in
                NavigationLink { CreditCardDetailView(cardID: card.id) } label: {
                    VStack(alignment: .leading) {
                        Text(card.name).font(.headline)
                        Text(card.isActive ? "Vencimento dia \(card.dueDay)" : "Inativo").font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Cartões")
        .proFinScreen()
        .toolbar { Button("Novo cartão", systemImage: "plus") { adding = true } }
        .sheet(isPresented: $adding) { CreditCardFormView() }
    }
}

struct CreditCardDetailView: View {
    let cardID: UUID
    @Query private var cards: [CreditCard]
    @State private var editing = false
    @State private var adding = false
    private var card: CreditCard? { cards.first { $0.id == cardID } }
    var body: some View {
        List {
            if let card {
                Section("Cartão") {
                    LabeledContent("Limite cadastrado", value: Money.formatted(card.limitInCents))
                    if let debt = try? CreditCardService.debt(card.invoices) {
                        LabeledContent("Dívida, incluindo parcelas futuras", value: Money.formatted(debt))
                        LabeledContent("Limite livre estimado", value: Money.formatted(max(0, card.limitInCents - debt)))
                    }
                    Text("Fechamento dia \(card.closingDay) · vencimento dia \(card.dueDay)")
                    if card.isActive { Button("Registrar compra", systemImage: "plus") { adding = true } }
                }
                Section {
                    NavigationLink("Parcelas dos próximos meses") { CardCommitmentsView(cardID: card.id) }
                    if let credit = try? CreditCardService.creditBalance(card.invoices), credit > 0 {
                        LabeledContent("Crédito restante no cartão", value: Money.formatted(credit))
                    }
                }
                Section("Faturas") {
                    ForEach(card.invoices.filter { !$0.installments.isEmpty || !$0.refunds.isEmpty }.sorted { $0.referenceMonth > $1.referenceMonth }) { invoice in
                        NavigationLink { CardInvoiceView(invoiceID: invoice.id) } label: {
                            VStack(alignment: .leading) {
                                Text(invoice.referenceMonth, format: .dateTime.month(.wide).year())
                                Text("\(CreditCardService.status(invoice)) · \((try? CreditCardService.total(invoice)).map(Money.formatted) ?? "Indisponível")")
                            }
                        }
                    }
                }
                Section("Compras") {
                    ForEach(card.purchases.sorted { $0.date > $1.date }) { purchase in
                        NavigationLink { CardPurchaseDetailView(purchaseID: purchase.id) } label: {
                            Text("\(purchase.title) · \(Money.formatted(purchase.amountInCents)) · \(purchase.installments.count)x")
                        }
                    }
                }
                Section { Text("O limite é estimado com as compras registradas. Confira a disponibilidade no banco. Alterar as datas do cartão não muda faturas já criadas.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(card?.name ?? "Cartão")
        .proFinScreen()
        .toolbar { Button("Editar") { editing = true } }
        .sheet(isPresented: $editing) { CreditCardFormView(cardID: cardID) }
        .sheet(isPresented: $adding) { CardPurchaseFormView(cardID: cardID) }
    }
}

struct CreditCardFormView: View {
    var cardID: UUID?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [CreditCard]
    @State private var name = ""
    @State private var limit = ""
    @State private var close = 3
    @State private var due = 10
    @State private var active = true
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome do cartão", text: $name)
                TextField("Limite em reais", text: $limit).keyboardType(.decimalPad)
                Stepper("Fechamento: dia \(close)", value: $close, in: 1...31)
                Stepper("Vencimento: dia \(due)", value: $due, in: 1...31)
                Toggle("Ativo para novas compras", isOn: $active)
                Text("Faturas existentes preservam suas datas. Dívidas continuam no planejamento mesmo com o cartão inativo. Dias inexistentes usam o último dia do mês.").font(.footnote)
            }
            .navigationTitle(cardID == nil ? "Novo cartão" : "Editar cartão")
            .proFinScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save) }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let card = cards.first(where: { $0.id == cardID }) {
                    name = card.name; limit = Money.input(card.limitInCents); close = card.closingDay; due = card.dueDay; active = card.isActive
                }
            }
            .alert("Não foi possível salvar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do {
            guard let limit = Money.cents(from: limit) else { throw CreditCardError.invalidCard }
            let card = cards.first { $0.id == cardID }
            if cardID != nil && card == nil { throw FinancialOperationError.differentContext }
            try CreditCardService.saveCard(card, name: name, limit: limit, closingDay: close, dueDay: due, active: active, in: context)
            dismiss()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Tente novamente. Os campos foram mantidos." }
    }
}
