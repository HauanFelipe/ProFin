import SwiftUI
import SwiftData

struct GoalDetailView: View {
    let goalID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [Goal]
    @State private var showingEdit = false
    @State private var confirmingDelete = false
    @State private var errorMessage: String?

    private var goal: Goal? { goals.first { $0.id == goalID } }

    var body: some View {
        Group {
            if let goal {
                List {
                    Section("Objetivo") {
                        LabeledContent("Valor desejado", value: Money.formatted(goal.targetAmountInCents))
                        GoalProgressView(goal: goal)
                        LabeledContent("Criada em") { Text(goal.createdAt, format: .dateTime.day().month().year()) }
                    }
                    Section {
                        if let account = goal.savingsAccount {
                            NavigationLink(account.name) { AccountDetailView(accountID: account.id) }
                        } else {
                            Text("Sem caixinha vinculada").foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Caixinha")
                    } footer: {
                        Text(goal.isArchived
                             ? "O vínculo foi preservado como referência. Para reativar, a caixinha precisa estar ativa e livre de outra meta."
                             : "Depósitos e retiradas alteram o progresso. Atingir o valor não registra uma compra e não indica, por si só, que o dinheiro está livre de outros compromissos.")
                    }
                    if !goal.isArchived {
                        Section {
                            NavigationLink("Analisar compra") { PurchaseAnalysisView(goalID: goalID) }
                        }
                    }
                    Section {
                        Button(goal.isArchived ? "Reativar meta" : "Arquivar meta") {
                            perform { try GoalOperations.setArchived(goal, archived: !goal.isArchived, in: context) }
                        }
                        Button("Excluir meta", role: .destructive) { confirmingDelete = true }
                    } footer: {
                        Text("Arquivar ou excluir libera a caixinha para outra meta e preserva o dinheiro e as movimentações.")
                    }
                }
                .navigationTitle(goal.name)
                .proFinScreen()
                .toolbar { Button("Editar") { showingEdit = true } }
            } else {
                ContentUnavailableView("Meta não encontrada", systemImage: "target")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) { GoalFormView(goalID: goalID) }
        .confirmationDialog("Excluir esta meta?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Excluir meta", role: .destructive) {
                guard let goal else { return }
                perform { try GoalOperations.delete(goal, in: context); dismiss() }
            }
        } message: { Text("O cadastro da meta será excluído. A caixinha e suas movimentações serão mantidas.") }
        .alert("Não foi possível alterar a meta", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Tente novamente."
        }
    }
}
