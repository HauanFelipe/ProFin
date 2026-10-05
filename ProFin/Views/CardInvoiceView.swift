import SwiftUI
import SwiftData

struct CardInvoiceView: View {
    let invoiceID: UUID
    @Query private var invoices: [CardInvoice]
    @Environment(\.modelContext) private var context
    @State private var paying = false
    @State private var undoing = false
    @State private var error: String?
    private var invoice: CardInvoice? { invoices.first { $0.id == invoiceID } }
    var body: some View {
        List {
            if let invoice {
                Section("Fatura") {
                    Text(invoice.card.name).font(.headline)
                    Text(invoice.referenceMonth, format: .dateTime.month(.wide).year())
                    Text(CreditCardService.status(invoice))
                    LabeledContent("Fechamento") { Text(invoice.closingDate, format: .dateTime.day().month().year()) }
                    LabeledContent("Vencimento") { Text(invoice.dueDate, format: .dateTime.day().month().year()) }
                    LabeledContent("Total", value: (try? CreditCardService.total(invoice)).map(Money.formatted) ?? "Indisponível")
                    if let balance = try? CreditCardService.balance(invoice) {
                        LabeledContent("Crédito anterior aplicado", value: Money.formatted(balance.appliedCredit))
                        LabeledContent("Ainda a pagar", value: Money.formatted(balance.pending))
                        if balance.remainingCredit > 0 { LabeledContent("Crédito para próximas faturas", value: Money.formatted(balance.remainingCredit)) }
                    }
                    if let payment = invoice.payment {
                        LabeledContent("Paga por", value: payment.account.name)
                        LabeledContent("Valor pago", value: Money.formatted(payment.amountInCents))
                        Button("Corrigir pagamento registrado por engano", role: .destructive) { undoing = true }
                        Text(payment.date, format: .dateTime.day().month().year())
                    } else if (try? CreditCardService.pending(invoice)) ?? 0 > 0 {
                        Button("Registrar pagamento integral") { paying = true }
                    }
                }
                Section("Compras e parcelas") {
                    ForEach(invoice.installments.sorted { $0.purchase.date < $1.purchase.date }) { installment in
                        NavigationLink { CardPurchaseDetailView(purchaseID: installment.purchase.id) } label: {
                            VStack(alignment: .leading) {
                                Text("\(installment.purchase.title) · \(installment.number)/\(installment.purchase.installments.count)")
                                Text(Money.formatted(installment.amountInCents))
                            }
                        }
                    }
                }
                Section("Estornos nesta fatura") {
                    ForEach(invoice.refunds) { refund in
                        NavigationLink { CardPurchaseDetailView(purchaseID: refund.purchase.id) } label: {
                            LabeledContent(refund.purchase.title, value: "− " + Money.formatted(refund.amountInCents))
                        }
                    }
                }
                Section { Text("Pagamento integral após o fechamento, descontando créditos. Pagamento parcial, rotativo e parcelamento da fatura ainda não são tratados. Corrigir um registro não movimenta dinheiro no banco.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Fatura")
        .proFinScreen()
        .confirmationDialog("Desfazer o registro de pagamento?", isPresented: $undoing, titleVisibility: .visible) {
            Button("Desfazer registro", role: .destructive) {
                guard let invoice else { return }
                do { try CreditCardService.undoPayment(invoice, in: context) }
                catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Não foi possível corrigir." }
            }
        } message: { Text("O valor voltará ao saldo calculado da conta e a fatura ficará pendente novamente. Use somente se o registro estava errado; isso não desfaz um pagamento no banco.") }
        .alert("Não foi possível corrigir", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .sheet(isPresented: $paying) { CardInvoicePaymentView(invoiceID: invoiceID) }
    }
}

private struct CardInvoicePaymentView: View {
    let invoiceID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var invoices: [CardInvoice]
    @Query(sort: \FinancialAccount.name) private var accounts: [FinancialAccount]
    @State private var accountID: UUID?
    @State private var date = Date()
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let invoice = invoices.first(where: { $0.id == invoiceID }) {
                    Text(invoice.card.name)
                    LabeledContent("Valor integral após créditos", value: (try? CreditCardService.pending(invoice)).map(Money.formatted) ?? "Indisponível")
                }
                Picker("Conta de pagamento", selection: $accountID) {
                    Text("Selecione").tag(nil as UUID?)
                    ForEach(accounts.filter(\.isActive)) { Text($0.name).tag(Optional($0.id)) }
                }
                if let account = accounts.first(where: { $0.id == accountID }) { AccountBalanceText(account: account) }
                DatePicker("Data", selection: $date, in: ...Date(), displayedComponents: .date)
                Text("Registre o pagamento que você fez no banco. O valor sai da conta escolhida e quita a fatura sem duplicar as compras.").font(.footnote)
            }
            .navigationTitle("Pagar fatura")
            .proFinScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Confirmar", action: save).disabled(accountID == nil) }
            }
            .alert("Não foi possível pagar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do {
            guard let invoice = invoices.first(where: { $0.id == invoiceID }), let account = accounts.first(where: { $0.id == accountID }) else { throw FinancialOperationError.differentContext }
            try CreditCardService.pay(invoice, from: account, date: date, in: context)
            dismiss()
        } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Não foi possível salvar. Tente novamente." }
    }
}
