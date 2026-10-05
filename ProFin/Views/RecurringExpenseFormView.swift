import SwiftUI
import SwiftData

struct RecurringExpenseFormView: View {
    var expenseID: UUID?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Category.name) private var categories: [Category]
    @Query private var expenses: [RecurringExpense]
    @State private var title = ""
    @State private var amountText = ""
    @State private var categoryID: UUID?
    @State private var dueDay = 10
    @State private var amountType = RecurringAmountType.fixed
    @State private var classification: ExpenseClassification?
    @State private var startMonth = Date()
    @State private var loaded = false
    @State private var errorMessage: String?
    @FocusState private var editingText: Bool

    private var expense: RecurringExpense? { expenses.first { $0.id == expenseID } }
    private var selectedCategory: Category? { categories.first { $0.id == categoryID && $0.isActive } }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && selectedCategory != nil && classification != nil
            && (Money.cents(from: amountText) != nil || (amountType == .variable && amountText.trimmingCharacters(in: .whitespaces).isEmpty))
            && (expenseID == nil || expense != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Conta recorrente") {
                    TextField("Descrição", text: $title).focused($editingText)
                    Picker("Categoria", selection: $categoryID) {
                        Text("Selecione").tag(nil as UUID?)
                        ForEach(categories.filter { $0.isActive }) { category in
                            Text(category.name).tag(Optional(category.id))
                        }
                    }
                    CreateCategoryButton(selection: $categoryID)
                    Picker("Tipo", selection: $amountType) {
                        ForEach(RecurringAmountType.allCases) { Text($0.title).tag($0) }
                    }
                    TextField(amountType == .fixed ? "Valor em reais" : "Estimativa em reais (opcional)", text: $amountText)
                        .keyboardType(.decimalPad).focused($editingText)
                    Picker("Classificação", selection: $classification) {
                        Text("Selecione").tag(nil as ExpenseClassification?)
                        ForEach(ExpenseClassification.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                }
                Section {
                    Stepper("Vencimento: dia \(dueDay)", value: $dueDay, in: 1...31)
                    LabeledContent("Frequência", value: "Mensal")
                    if expenseID == nil {
                        DatePicker("Começar no mês de", selection: $startMonth, displayedComponents: .date)
                    }
                } footer: {
                    Text("Em meses mais curtos, o vencimento será no último dia. Apenas o mês e o ano da data inicial são usados.")
                }
                Section {
                    Text(expenseID == nil
                         ? "Cadastrar cria previsões, sem registrar pagamentos. Uma conta variável sem estimativa deixará os totais previstos incompletos."
                         : "As alterações valem para as próximas cobranças ainda não geradas. As cobranças do mês atual e dos meses anteriores serão preservadas.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Use vírgula para os centavos. Exemplo: 650,00.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !amountText.isEmpty && Money.cents(from: amountText) == nil {
                        Text("Informe um valor positivo válido ou deixe a estimativa variável em branco.")
                            .foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle(expenseID == nil ? "Nova conta recorrente" : "Editar conta recorrente")
            .proFinScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(!canSave) }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Concluir") { editingText = false }
                }
            }
            .task {
                guard !loaded else { return }
                if let expense {
                    title = expense.title
                    if let amount = expense.expectedAmountInCents { amountText = Money.input(amount) }
                    categoryID = expense.category.id
                    dueDay = expense.dueDay
                    amountType = expense.amountType
                    classification = expense.classification
                    startMonth = expense.startMonth
                }
                loaded = true
            }
            .alert("Não foi possível salvar", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard canSave, let category = selectedCategory, let classification else { return }
        do {
            if let expense {
                try RecurringExpenseOperations.update(
                    expense, title: title, category: category, expectedAmountInCents: Money.cents(from: amountText),
                    dueDay: dueDay, amountType: amountType, classification: classification, in: context
                )
            } else {
                try RecurringExpenseOperations.create(
                    title: title, category: category, expectedAmountInCents: Money.cents(from: amountText),
                    dueDay: dueDay, amountType: amountType, classification: classification,
                    startMonth: startMonth, in: context
                )
            }
            dismiss()
        } catch {
            errorMessage = (error as? RecurringExpenseError)?.errorDescription
                ?? "Verifique os campos e tente novamente. Suas informações foram mantidas no formulário."
        }
    }
}
