import SwiftUI
import SwiftData

struct RecurringPaymentView: View {
    let occurrenceID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var occurrences: [RecurringExpenseOccurrence]
    @Query(sort: \FinancialAccount.name) private var accounts: [FinancialAccount]
    @Query(sort: \FinancialTransaction.date, order: .reverse) private var transactions: [FinancialTransaction]
    @State private var linkingExisting = false
    @State private var amountText = ""
    @State private var date = Date()
    @State private var accountID: UUID?
    @State private var transactionID: UUID?
    @State private var notes = ""
    @State private var loaded = false
    @State private var errorMessage: String?
    @FocusState private var editingText: Bool

    private var occurrence: RecurringExpenseOccurrence? { occurrences.first { $0.id == occurrenceID } }
    private var availableTransactions: [FinancialTransaction] {
        transactions.filter { $0.type == .expense && $0.recurringOccurrence == nil && $0.account != nil }
    }
    private var canSave: Bool {
        guard let occurrence, occurrence.paymentTransaction == nil else { return false }
        if linkingExisting { return availableTransactions.contains { $0.id == transactionID } }
        return Money.cents(from: amountText) != nil && accounts.contains { $0.id == accountID && $0.isActive }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let occurrence {
                    Section("Cobrança") {
                        Text(occurrence.title).font(.headline)
                        LabeledContent("Referência") {
                            Text(occurrence.referenceMonth, format: .dateTime.month(.wide).year())
                        }
                        LabeledContent("Previsto", value: occurrence.expectedAmountInCents.map(Money.formatted) ?? "Sem estimativa")
                        LabeledContent("Categoria", value: occurrence.category.name)
                    }
                    if occurrence.paymentTransaction != nil {
                        Text("Esta cobrança já foi paga.")
                    } else {
                        Section {
                            Toggle("Usar despesa já registrada", isOn: $linkingExisting)
                        } footer: {
                            Text("Se você já lançou este pagamento em Movimentações, vincule a despesa existente para não registrá-la duas vezes.")
                        }
                        if linkingExisting {
                            Section("Escolha a despesa") {
                                if availableTransactions.isEmpty { Text("Nenhuma despesa disponível para vincular.") }
                                ForEach(availableTransactions) { transaction in
                                    Button {
                                        transactionID = transaction.id
                                    } label: {
                                        HStack(alignment: .top) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(transaction.title).font(.headline)
                                                Text(Money.formatted(transaction.amountInCents))
                                                Text(transaction.date, format: .dateTime.day().month().year())
                                                Text("\(transaction.category.name) · \(transaction.account?.name ?? "")")
                                                    .font(.caption)
                                            }
                                            Spacer()
                                            if transaction.id == transactionID { Image(systemName: "checkmark.circle.fill") }
                                        }
                                    }
                                    .foregroundStyle(.primary)
                                }
                            }
                        } else {
                            Section("Pagamento realizado") {
                                TextField("Valor pago em reais", text: $amountText)
                                    .keyboardType(.decimalPad).focused($editingText)
                                DatePicker("Data do pagamento", selection: $date, in: ...Date(), displayedComponents: .date)
                                Picker("Conta", selection: $accountID) {
                                    Text("Selecione").tag(nil as UUID?)
                                    ForEach(accounts.filter { $0.isActive }) { Text($0.name).tag(Optional($0.id)) }
                                }
                                TextField("Observação (opcional)", text: $notes, axis: .vertical)
                                    .lineLimit(2...5).focused($editingText)
                            }
                            Section {
                                Text("Confirme o valor efetivamente pago, mesmo se ele diferir da previsão. Será criada uma única despesa na data informada.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Cobrança indisponível. Reabra a lista.")
                }
            }
            .navigationTitle("Registrar pagamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Confirmar", action: save).disabled(!canSave) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Concluir") { editingText = false }
                }
            }
            .task {
                guard !loaded else { return }
                if let amount = occurrence?.expectedAmountInCents { amountText = Money.input(amount) }
                let active = accounts.filter { $0.isActive }
                if active.count == 1 { accountID = active.first?.id }
                loaded = true
            }
            .alert("Não foi possível registrar", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard canSave, let occurrence else { return }
        do {
            if linkingExisting {
                guard let transaction = availableTransactions.first(where: { $0.id == transactionID }) else { return }
                try FinancialOperations.linkPayment(transaction, to: occurrence, in: context)
            } else {
                guard let amount = Money.cents(from: amountText),
                      let account = accounts.first(where: { $0.id == accountID }) else { return }
                try FinancialOperations.payRecurringExpense(
                    occurrence, amountInCents: amount, date: date, account: account, notes: notes, in: context
                )
            }
            dismiss()
        } catch {
            errorMessage = (error as? RecurringExpenseError)?.errorDescription
                ?? "Verifique a conta e a categoria e tente novamente. Seus campos foram mantidos."
        }
    }
}
