import SwiftUI
import SwiftData

struct GoalFormView: View {
    var goalID: UUID?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [Goal]
    @Query(sort: \FinancialAccount.name) private var accounts: [FinancialAccount]
    @State private var name = ""
    @State private var targetText = ""
    @State private var accountID: UUID?
    @State private var loaded = false
    @State private var errorMessage: String?

    private var goal: Goal? { goals.first { $0.id == goalID } }
    private var availableAccounts: [FinancialAccount] {
        accounts.filter { account in
            if account.id == goal?.savingsAccount?.id { return true }
            guard account.isActive, !account.isEmergencyReserve, account.kind == .savingsBox else { return false }
            return goal?.isArchived == true || !goals.contains { !$0.isArchived && $0.id != goalID && $0.savingsAccount?.id == account.id }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Objetivo") {
                    TextField("Nome da meta", text: $name)
                    TextField("Valor desejado em reais", text: $targetText).keyboardType(.decimalPad)
                }
                Section {
                    Picker("Caixinha", selection: $accountID) {
                        Text("Sem vínculo").tag(nil as UUID?)
                        ForEach(availableAccounts) { account in
                            Text("\(account.name)\(account.isActive ? "" : " · Inativa")").tag(Optional(account.id))
                        }
                    }
                    if availableAccounts.isEmpty {
                        Text("Crie uma caixinha na aba Caixinhas ou libere uma que esteja vinculada a outra meta.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Cada caixinha atende somente uma meta ativa. Vincular não transfere dinheiro: o progresso acompanha o saldo registrado. Projeções de rendimento não entram nesse saldo.")
                }
            }
            .navigationTitle(goalID == nil ? "Nova meta" : "Editar meta")
            .proFinScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save) }
            }
            .onAppear {
                guard !loaded else { return }
                if let goal {
                    name = goal.name
                    targetText = Money.input(goal.targetAmountInCents)
                    accountID = goal.savingsAccount?.id
                }
                loaded = true
            }
            .alert("Não foi possível salvar", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        do {
            guard let target = Money.cents(from: targetText) else { throw GoalOperationError.invalidTarget }
            let account = accounts.first { $0.id == accountID }
            if accountID != nil && account == nil { throw GoalOperationError.invalidAccount }
            if goalID != nil {
                guard let goal else { throw FinancialOperationError.differentContext }
                try GoalOperations.update(goal, name: name, targetAmountInCents: target, account: account, in: context)
            } else {
                try GoalOperations.create(name: name, targetAmountInCents: target, account: account, in: context)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Tente novamente. Os campos foram mantidos."
        }
    }
}
