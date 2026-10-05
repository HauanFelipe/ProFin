import SwiftUI
import SwiftData

struct CardPurchaseFormView: View {
    let cardID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var cards: [CreditCard]
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var occurrences: [RecurringExpenseOccurrence]
    @State private var title = ""
    @State private var amount = ""
    @State private var date = Date()
    @State private var count = 1
    @State private var month = Date()
    @State private var manualMonth = false
    @State private var categoryID: UUID?
    @State private var classification: ExpenseClassification = .essential
    @State private var occurrenceID: UUID?
    @State private var notes = ""
    @State private var loaded = false
    @State private var error: String?
    private var card: CreditCard? { cards.first { $0.id == cardID } }
    var body: some View {
        NavigationStack {
            Form {
                Section("Compra") {
                    TextField("Descrição", text: $title)
                    TextField("Valor TOTAL em reais", text: $amount).keyboardType(.decimalPad)
                    DatePicker("Data da compra", selection: $date, in: ...Date(), displayedComponents: .date)
                    Picker("Categoria", selection: $categoryID) {
                        Text("Selecione").tag(nil as UUID?)
                        ForEach(categories.filter(\.isActive)) { Text($0.name).tag(Optional($0.id)) }
                    }
                    CreateCategoryButton(selection: $categoryID)
                    Picker("Classificação", selection: $classification) {
                        ForEach(ExpenseClassification.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section {
                    Stepper("Parcelas: \(count)", value: $count, in: 1...120)
                    Toggle("Ajustar primeira fatura", isOn: $manualMonth)
                    if manualMonth { DatePicker("Mês do vencimento", selection: $month, displayedComponents: .date) }
                    LabeledContent("Primeira fatura") { Text(month, format: .dateTime.month(.wide).year()) }
                    Text("Informe o total final da compra, inclusive juros se houver. O app divide os centavos sem alterar esse total. Compras no dia do fechamento vão por padrão à próxima fatura; confira com o banco.").font(.footnote)
                }
                Section {
                    Picker("Cobrança recorrente", selection: $occurrenceID) {
                        Text("Nenhuma").tag(nil as UUID?)
                        ForEach(occurrences.filter { $0.paymentTransaction == nil && $0.cardPurchase == nil }.sorted { $0.dueDate > $1.dueDate }) { occurrence in
                            Text("\(occurrence.title) · \(occurrence.referenceMonth.formatted(.dateTime.month().year().locale(Locale(identifier: "pt_BR"))))").tag(Optional(occurrence.id))
                        }
                    }
                    Text("Se esta compra paga uma cobrança recorrente, selecione-a para não descontá-la novamente fora da fatura.").font(.footnote)
                    TextField("Observação (opcional)", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Compra no cartão")
            .proFinScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save) }
            }
            .onAppear {
                if !loaded {
                    loaded = true; updateMonth()
                    do { try RecurringExpenseOperations.generateDueOccurrences(in: context) }
                    catch { self.error = "Não foi possível atualizar as cobranças recorrentes. Reabra o formulário antes de vincular uma cobrança." }
                }
            }
            .onChange(of: date) { _, _ in updateMonth() }
            .onChange(of: manualMonth) { _, _ in updateMonth() }
            .alert("Confira os dados", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func updateMonth() {
        if !manualMonth, let card, let first = try? CreditCardService.firstMonth(for: date, card: card) { month = first }
    }
    private func save() {
        do {
            guard let card, let category = categories.first(where: { $0.id == categoryID }), let cents = Money.cents(from: amount) else { throw CreditCardError.invalidPurchase }
            let occurrence = occurrences.first { $0.id == occurrenceID }
            if occurrenceID != nil && occurrence == nil { throw CreditCardError.alreadyLinked }
            try CreditCardService.purchase(card: card, title: title, amount: cents, date: date, category: category,
                classification: classification, count: count, firstMonth: month, notes: notes,
                occurrence: occurrence, in: context)
            dismiss()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Não foi possível salvar. Seus campos foram mantidos." }
    }
}

struct CardPurchaseDetailView: View {
    let purchaseID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var purchases: [CardPurchase]
    @Query private var occurrences: [RecurringExpenseOccurrence]
    @State private var occurrenceID: UUID?
    @State private var confirmingDelete = false
    @State private var showingRefund = false
    @State private var deletingRefundID: UUID?
    @State private var error: String?
    private var purchase: CardPurchase? { purchases.first { $0.id == purchaseID } }
    var body: some View {
        List {
            if let purchase {
                Section("Compra") {
                    Text(purchase.title).font(.headline)
                    LabeledContent("Total", value: Money.formatted(purchase.amountInCents))
                    LabeledContent("Cartão", value: purchase.card.name)
                    LabeledContent("Categoria", value: purchase.category.name)
                    LabeledContent("Classificação", value: purchase.classification.title)
                    Text(purchase.date, format: .dateTime.day().month().year())
                    if let notes = purchase.notes { Text(notes) }
                }
                Section("Parcelas") {
                    ForEach(purchase.installments.sorted { $0.number < $1.number }) { installment in
                        NavigationLink { CardInvoiceView(invoiceID: installment.invoice.id) } label: {
                            VStack(alignment: .leading) {
                                Text("\(installment.number)/\(purchase.installments.count) · \(Money.formatted(installment.amountInCents))")
                                Text(installment.invoice.dueDate, format: .dateTime.day().month().year())
                            }
                        }
                    }
                }
                Section("Estornos") {
                    Button("Registrar estorno") { showingRefund = true }
                    ForEach(purchase.refunds.sorted { $0.date > $1.date }) { refund in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Money.formatted(refund.amountInCents))
                            Text(refund.date, format: .dateTime.day().month().year())
                            Text("Fatura: \(refund.invoice.referenceMonth.formatted(.dateTime.month().year().locale(Locale(identifier: "pt_BR"))))")
                            if let notes = refund.notes { Text(notes) }
                            Button("Remover estorno registrado por engano", role: .destructive) { deletingRefundID = refund.id }
                        }
                    }
                }
                Section("Cobrança recorrente") {
                    if let occurrence = purchase.recurringOccurrence { Text("Vinculada a \(occurrence.title). A pendência é considerada somente na fatura.") }
                    else {
                        Picker("Vincular cobrança existente", selection: $occurrenceID) {
                            Text("Selecione").tag(nil as UUID?)
                            ForEach(occurrences.filter { $0.paymentTransaction == nil && $0.cardPurchase == nil }) {
                                Text("\($0.title) · \($0.referenceMonth.formatted(.dateTime.month().year().locale(Locale(identifier: "pt_BR"))))").tag(Optional($0.id))
                            }
                        }
                        Button("Vincular sem novo lançamento") {
                            perform {
                                guard let occurrence = occurrences.first(where: { $0.id == occurrenceID }) else { throw CreditCardError.alreadyLinked }
                                try CreditCardService.link(purchase, to: occurrence, in: context)
                            }
                        }.disabled(occurrenceID == nil)
                    }
                }
                Section {
                    Button("Excluir compra", role: .destructive) { confirmingDelete = true }
                } footer: { Text("Para corrigir uma compra, exclua e cadastre novamente. Compras com parcelas pagas não podem ser excluídas.") }
            }
        }
        .navigationTitle("Compra")
        .proFinScreen()
        .sheet(isPresented: $showingRefund) { CardRefundFormView(purchaseID: purchaseID) }
        .confirmationDialog("Remover este registro de estorno?", isPresented: Binding(get: { deletingRefundID != nil }, set: { if !$0 { deletingRefundID = nil } }), titleVisibility: .visible) {
            Button("Remover registro", role: .destructive) {
                guard let refund = purchase?.refunds.first(where: { $0.id == deletingRefundID }) else { return }
                perform { try CreditCardService.deleteRefund(refund, in: context) }
                deletingRefundID = nil
            }
        } message: { Text("Os valores das faturas serão recalculados. Isso não cancela um estorno no banco.") }
        .confirmationDialog("Excluir compra e suas parcelas?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Excluir", role: .destructive) {
                guard let purchase else { return }
                perform { try CreditCardService.deletePurchase(purchase, in: context); dismiss() }
            }
        } message: { Text("Uma cobrança recorrente vinculada voltará a ficar pendente.") }
        .alert("Não foi possível concluir", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Tente novamente." }
    }
}
