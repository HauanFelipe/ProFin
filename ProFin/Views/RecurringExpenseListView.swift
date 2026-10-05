import SwiftUI
import SwiftData

struct RecurringExpenseListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RecurringExpense.title) private var expenses: [RecurringExpense]
    @State private var selection: Selection?
    @State private var pendingDeactivation: UUID?
    @State private var showingError = false

    private struct Selection: Identifiable {
        let id: UUID
        let reactivating: Bool
    }

    var body: some View {
        List {
            if expenses.isEmpty { Text("Cadastre sua primeira conta pelo botão + na tela de recorrências.") }
            ForEach(expenses) { expense in
                VStack(alignment: .leading, spacing: 8) {
                    Text(expense.title).font(.headline)
                    Text("\(expense.amountType.title) · Mensal · Dia \(expense.dueDay)")
                        .font(.subheadline)
                    Text(expense.expectedAmountInCents.map(Money.formatted) ?? "Sem estimativa")
                    Text(expense.isActive ? "Ativa" : "Inativa").foregroundStyle(.secondary)
                    HStack {
                        Button("Editar") { selection = Selection(id: expense.id, reactivating: false) }
                        Spacer()
                        if expense.isActive {
                            Button("Desativar", role: .destructive) { pendingDeactivation = expense.id }
                        } else {
                            Button("Reativar") { selection = Selection(id: expense.id, reactivating: true) }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Gerenciar contas")
        .proFinScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selection) { selection in
            if selection.reactivating {
                RecurringReactivationView(expenseID: selection.id)
            } else {
                RecurringExpenseFormView(expenseID: selection.id)
            }
        }
        .confirmationDialog("Desativar esta conta?", isPresented: Binding(
            get: { pendingDeactivation != nil }, set: { if !$0 { pendingDeactivation = nil } }
        ), titleVisibility: .visible) {
            Button("Desativar", role: .destructive) { deactivate() }
            Button("Cancelar", role: .cancel) { pendingDeactivation = nil }
        } message: {
            Text("As cobranças até o mês atual, incluindo as pendentes, serão preservadas. Os próximos meses não serão gerados.")
        }
        .alert("Não foi possível desativar", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Tente novamente. Os pagamentos existentes foram preservados.") }
    }

    private func deactivate() {
        guard let expense = expenses.first(where: { $0.id == pendingDeactivation }) else { return }
        do { try RecurringExpenseOperations.setActive(expense, active: false, in: context) }
        catch { showingError = true }
        pendingDeactivation = nil
    }
}

private struct RecurringReactivationView: View {
    let expenseID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var expenses: [RecurringExpense]
    @State private var start = Date()
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Retomar no mês de", selection: $start, in: Date()..., displayedComponents: .date)
                Text("Somente o mês e o ano são considerados. O intervalo inativo não será preenchido. Cobranças já existentes serão preservadas.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Reativar conta")
            .proFinScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reativar") {
                        guard let expense = expenses.first(where: { $0.id == expenseID }) else { return }
                        do {
                            try RecurringExpenseOperations.setActive(expense, active: true, startingIn: start, in: context)
                            dismiss()
                        } catch { showingError = true }
                    }
                }
            }
            .alert("Não foi possível reativar", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Escolha o mês atual ou um mês futuro e tente novamente.") }
        }
    }
}
