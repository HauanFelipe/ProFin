import SwiftUI
import SwiftData

struct TransactionFormView: View {
    private enum Field: Hashable {
        case title, amount, notes
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Category> { $0.isActive }, sort: \Category.name)
    private var categories: [Category]
    @Query(filter: #Predicate<FinancialAccount> { $0.isActive }, sort: \FinancialAccount.name)
    private var accounts: [FinancialAccount]

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var type = TransactionType.expense
    @State private var categoryID: UUID?
    @State private var accountID: UUID?
    @State private var classification: ExpenseClassification?
    @State private var notes = ""
    @State private var showingSaveError = false
    @FocusState private var focusedField: Field?

    private var selectedCategory: Category? {
        categories.first { $0.id == categoryID }
    }

    private var selectedAccount: FinancialAccount? {
        accounts.first { $0.id == accountID }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Money.cents(from: amountText) != nil
            && selectedCategory != nil
            && selectedAccount != nil
            && (type == .income || classification != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Movimentação") {
                    Picker("Tipo", selection: $type) {
                        ForEach(TransactionType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Descrição", text: $title)
                        .textInputAutocapitalization(.sentences)
                        .focused($focusedField, equals: .title)

                    TextField("Valor em reais", text: $amountText)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Valor em reais")
                        .focused($focusedField, equals: .amount)

                    DatePicker("Data", selection: $date, in: ...Date(), displayedComponents: .date)
                }

                Section {
                    Picker("Conta", selection: $accountID) {
                        Text("Selecione").tag(nil as UUID?)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }

                    Picker("Categoria", selection: $categoryID) {
                        Text("Selecione").tag(nil as UUID?)
                        ForEach(categories) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }

                    CreateCategoryButton(selection: $categoryID)

                    if type == .expense {
                        Picker("Classificação", selection: $classification) {
                            Text("Selecione").tag(nil as ExpenseClassification?)
                            ForEach(ExpenseClassification.allCases) { classification in
                                Text(classification.title).tag(Optional(classification))
                            }
                        }
                    }
                } footer: {
                    if type == .expense {
                        Text("Escolha se esta despesa é essencial ou não essencial para você.")
                    }
                }

                Section("Observação (opcional)") {
                    TextField("Adicione uma observação", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .notes)
                }

                Section {
                    Text("Preencha a descrição, um valor maior que zero, a conta e a categoria. Para despesas, escolha também a classificação. Use vírgula para os centavos: 1.234,56.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if !amountText.isEmpty && Money.cents(from: amountText) == nil {
                        Label("Informe um valor válido. Exemplo: 25,90.", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Nova movimentação")
            .proFinScreen()
            .onChange(of: accounts.map(\.id), initial: true) { _, ids in
                if accountID == nil, ids.count == 1 { accountID = ids.first }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: saveTransaction)
                        .disabled(!canSave)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Concluir") {
                        focusedField = nil
                    }
                }
            }
            .alert("Não foi possível salvar", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Seus campos foram mantidos. Tente salvar novamente.")
            }
        }
    }

    private func saveTransaction() {
        guard canSave,
              let amount = Money.cents(from: amountText),
              let category = selectedCategory,
              let account = selectedAccount else { return }

        do {
            try FinancialOperations.recordTransaction(
                title: title, amountInCents: amount, date: date, category: category,
                type: type, account: account, classification: classification,
                notes: notes, in: modelContext
            )
            dismiss()
        } catch {
            showingSaveError = true
        }
    }
}
