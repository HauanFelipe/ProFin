import SwiftUI
import SwiftData

struct TransactionListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FinancialTransaction.date, order: .reverse)
    private var transactions: [FinancialTransaction]

    @State private var showingForm = false
    @State private var showingDeleteError = false
    @State private var pendingDeletionIDs: [UUID] = []
    @State private var confirmingPaymentDeletion = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        RecurringExpensesView()
                    } label: {
                        Label("Contas recorrentes", systemImage: "calendar.badge.clock")
                    }
                }
                Section("Receitas e despesas realizadas") {
                    if transactions.isEmpty {
                        ContentUnavailableView {
                            Label("Nenhuma movimentação", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text("Registre sua primeira receita ou despesa.")
                        } actions: {
                            Button("Adicionar movimentação") { showingForm = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    ForEach(transactions) { transaction in
                        NavigationLink {
                            TransactionDetailView(transaction: transaction)
                        } label: {
                            TransactionRow(transaction: transaction)
                        }
                    }
                    .onDelete(perform: requestDeletion)
                }
            }
            .navigationTitle("Movimentações")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !transactions.isEmpty { EditButton() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Adicionar movimentação", systemImage: "plus") { showingForm = true }
                }
            }
            .sheet(isPresented: $showingForm) { TransactionFormView() }
            .confirmationDialog("Excluir pagamento?", isPresented: $confirmingPaymentDeletion, titleVisibility: .visible) {
                Button("Excluir e reabrir cobrança", role: .destructive) { deleteTransactions(ids: pendingDeletionIDs) }
                Button("Cancelar", role: .cancel) { pendingDeletionIDs = [] }
            } message: {
                Text("A exclusão remove a despesa realizada. A conta recorrente correspondente voltará a ficar pendente.")
            }
            .alert("Não foi possível excluir", isPresented: $showingDeleteError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("A movimentação foi mantida. Tente novamente.")
            }
        }
    }

    private func requestDeletion(at offsets: IndexSet) {
        let selected = offsets.map { transactions[$0] }
        if selected.contains(where: { $0.recurringOccurrence != nil }) {
            pendingDeletionIDs = selected.map(\.id)
            confirmingPaymentDeletion = true
        } else {
            deleteTransactions(ids: selected.map(\.id))
        }
    }

    private func deleteTransactions(ids: [UUID]) {
        do {
            try FinancialOperations.deleteTransactions(transactions.filter { ids.contains($0.id) }, in: modelContext)
        } catch {
            showingDeleteError = true
        }
        pendingDeletionIDs = []
    }
}
