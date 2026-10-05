import SwiftUI
import SwiftData

struct CardRefundFormView: View {
    let purchaseID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var purchases: [CardPurchase]
    @State private var amount = ""
    @State private var date = Date()
    @State private var month = Date()
    @State private var notes = ""
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if let purchase = purchases.first(where: { $0.id == purchaseID }) {
                    Text(purchase.title).font(.headline)
                    TextField("Valor estornado (R$)", text: $amount).keyboardType(.decimalPad)
                    DatePicker("Data do crédito", selection: $date, in: purchase.date...Date(), displayedComponents: .date)
                    DatePicker("Mês de vencimento da fatura", selection: $month, displayedComponents: .date)
                    TextField("Observação opcional", text: $notes)
                    Text("Escolha a fatura em que o banco lançou o crédito. O dia escolhido no campo da fatura é ignorado. O estorno reduz essa fatura; o excedente abate as seguintes. Não é receita nem dinheiro recebido na conta.")
                    Text("As parcelas originais continuam no histórico. Registre somente o crédito efetivamente lançado pelo banco. Se o banco também cancelar parcelas, não registre os dois ajustes para o mesmo valor.")
                }
            }
            .navigationTitle("Registrar estorno")
            .proFinScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") {
                    do {
                        guard let purchase = purchases.first(where: { $0.id == purchaseID }), let amount = Money.cents(from: amount) else { throw CreditCardError.invalidRefund }
                        try CreditCardService.refund(purchase: purchase, amount: amount, date: date, month: month, notes: notes.isEmpty ? nil : notes, in: context)
                        dismiss()
                    } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Não foi possível salvar." }
                } }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let purchase = purchases.first(where: { $0.id == purchaseID }),
                   let suggested = try? CreditCardService.firstMonth(for: date, card: purchase.card) { month = suggested }
            }
            .alert("Confira o estorno", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}
