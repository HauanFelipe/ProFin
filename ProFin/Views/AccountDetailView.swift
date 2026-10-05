import SwiftUI
import SwiftData

struct AccountDetailView: View {
    let accountID: UUID
    @Environment(\.modelContext) private var context
    @Query private var accounts: [FinancialAccount]
    @State private var showingEdit = false
    @State private var showingDeposit = false
    @State private var showingWithdrawal = false
    @State private var confirmingDeactivation = false
    @State private var errorMessage: String?

    private var account: FinancialAccount? { accounts.first { $0.id == accountID } }

    var body: some View {
        Group {
            if let account {
                List {
                    Section("Saldo atual") {
                        AccountBalanceText(account: account).font(.title.bold())
                        if account.isEmergencyReserve { Label("Reserva de emergência protegida", systemImage: "shield") }
                        LabeledContent("Tipo", value: account.kind.title)
                        LabeledContent("Situação", value: account.isActive ? "Ativa" : "Inativa")
                        if let createdAt = account.createdAt {
                            LabeledContent("Criada em") { Text(createdAt, format: .dateTime.day().month().year()) }
                        }
                    }
                    if account.isActive {
                        Section {
                            Button("Adicionar dinheiro", systemImage: "arrow.down.left") { showingDeposit = true }
                            Button(account.kind == .savingsBox ? "Retirar da caixinha" : "Transferir dinheiro", systemImage: "arrow.up.right") {
                                showingWithdrawal = true
                            }
                        } footer: {
                            Text("Estas ações transferem dinheiro entre suas contas.")
                        }
                    }
                    if account.kind == .savingsBox {
                        Section {
                            NavigationLink("Rendimento estimado") { SavingsYieldView(accountID: accountID) }
                        }
                    }
                    Section("Histórico") {
                        let entries = AccountHistory.entries(for: account)
                        if entries.isEmpty {
                            Text("Nenhuma movimentação registrada.").foregroundStyle(.secondary)
                        }
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.title).font(.headline)
                                Text(entry.detail).font(.subheadline).foregroundStyle(.secondary)
                                Text("\(entry.isIncoming ? "+" : "−") \(Money.formatted(entry.amountInCents))")
                                    .fontWeight(.semibold)
                                Text(entry.date, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary)
                                if let notes = entry.notes { Text(notes).font(.subheadline) }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    Section {
                        Button(account.isActive ? "Desativar conta" : "Reativar conta") {
                            if account.isActive { confirmingDeactivation = true } else { changeActive(to: true) }
                        }
                    } footer: {
                        Text("Para desativar, o saldo precisa estar zerado. O histórico será preservado.")
                    }
                }
                .navigationTitle(account.name)
                .proFinScreen()
                .toolbar { Button("Editar") { showingEdit = true } }
            } else {
                ContentUnavailableView("Conta não encontrada", systemImage: "questionmark.folder")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) { AccountFormView(accountID: accountID) }
        .sheet(isPresented: $showingDeposit) { TransferFormView(initialDestinationID: accountID) }
        .sheet(isPresented: $showingWithdrawal) { TransferFormView(initialSourceID: accountID) }
        .confirmationDialog("Desativar esta conta?", isPresented: $confirmingDeactivation, titleVisibility: .visible) {
            Button("Desativar", role: .destructive) { changeActive(to: false) }
        } message: { Text("A conta ficará fora do patrimônio total e da seleção de novas movimentações.") }
        .alert("Não foi possível alterar a conta", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func changeActive(to active: Bool) {
        guard let account else { return }
        do {
            try FinancialOperations.setAccountActive(account, active: active, in: context)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Tente novamente."
        }
    }
}
