import SwiftUI
import SwiftData

struct AccountFormView: View {
    var accountID: UUID?
    var defaultKind: FinancialAccountKind = .checking
    var requiresCurrentBalance = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [FinancialAccount]
    @State private var name = ""
    @State private var kind = FinancialAccountKind.checking
    @State private var currentBalanceText = "0,00"
    @State private var isEmergencyReserve = false
    @State private var loaded = false
    @State private var errorMessage: String?

    private var account: FinancialAccount? { accounts.first { $0.id == accountID } }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (Money.balanceCents(from: currentBalanceText) != nil || (!requiresCurrentBalance && account?.openingBalanceInCents == nil && accountID != nil && currentBalanceText.isEmpty))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Conta") {
                    TextField("Nome", text: $name)
                    Picker("Tipo", selection: $kind) {
                        ForEach(FinancialAccountKind.allCases) { Text($0.title).tag($0) }
                    }
                }
                if kind == .savingsBox || isEmergencyReserve {
                    Section {
                        Toggle("Proteger como reserva de emergência", isOn: $isEmergencyReserve)
                    } footer: {
                        Text("Essa caixinha fica fora da análise de compra. Se houver uma meta ativa vinculada, desvincule ou arquive a meta antes de proteger a reserva. Transferências continuam disponíveis.")
                    }
                }
                Section {
                    TextField("Quanto você tem agora (R$)", text: $currentBalanceText)
                        .keyboardType(.numbersAndPunctuation)
                        .disabled(account?.isActive == false)
                    if !currentBalanceText.isEmpty && Money.balanceCents(from: currentBalanceText) == nil {
                        Text("Informe um valor válido, como 0,00, 1.000,00 ou -50,00.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                } header: {
                    Text(kind == .savingsBox ? "Dinheiro na caixinha" : "Dinheiro na conta")
                } footer: {
                    Text(kind == .savingsBox
                         ? "Informe quanto você tem nesta caixinha agora. Não inclua dinheiro de outras contas."
                         : "Informe quanto você tem nesta conta agora, sem incluir o dinheiro das caixinhas. O app considera os lançamentos já cadastrados para não contar o mesmo dinheiro duas vezes.")
                }
            }
            .navigationTitle(accountID == nil ? "Nova conta" : "Editar conta")
            .proFinScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(!canSave) }
            }
            .onAppear {
                guard !loaded else { return }
                if let account {
                    name = account.name
                    kind = account.kind
                    isEmergencyReserve = account.isEmergencyReserve
                    do {
                        currentBalanceText = try FinancialSummary.balance(of: account).map(Money.input) ?? ""
                    } catch {
                        currentBalanceText = ""
                        errorMessage = "Não foi possível calcular o dinheiro na conta. Confira os lançamentos antes de ajustar o valor."
                    }
                } else {
                    kind = defaultKind
                }
                loaded = true
            }
            .alert("Não foi possível salvar", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            if accountID != nil {
                guard let account else { throw FinancialOperationError.differentContext }
                try FinancialOperations.updateAccountCurrentBalance(account, name: name, kind: kind,
                    currentBalanceInCents: Money.balanceCents(from: currentBalanceText), isEmergencyReserve: isEmergencyReserve, in: context)
            } else {
                guard let opening = Money.balanceCents(from: currentBalanceText) else { throw AccountOperationError.missingOpeningBalance }
                try FinancialOperations.createAccount(name: name, kind: kind, openingBalanceInCents: opening, isEmergencyReserve: isEmergencyReserve, in: context)
            }
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Tente novamente. Os campos foram mantidos."
        }
    }
}
