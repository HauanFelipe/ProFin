import SwiftUI
import SwiftData

struct TransferFormView: View {
    var initialSourceID: UUID?
    var initialDestinationID: UUID?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<FinancialAccount> { $0.isActive }, sort: \FinancialAccount.name)
    private var accounts: [FinancialAccount]
    @State private var sourceID: UUID?
    @State private var destinationID: UUID?
    @State private var amountText = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var loaded = false
    @State private var errorMessage: String?
    @State private var showingSourceSetup = false

    private var source: FinancialAccount? { accounts.first { $0.id == sourceID } }
    private var destination: FinancialAccount? { accounts.first { $0.id == destinationID } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Origem", selection: $sourceID) {
                        Text("Selecione").tag(nil as UUID?)
                        ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Destino", selection: $destinationID) {
                        Text("Selecione").tag(nil as UUID?)
                        ForEach(accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    if let source {
                        LabeledContent("Saldo atual da origem") { AccountBalanceText(account: source) }
                        if source.openingBalanceInCents == nil {
                            Text("Informe quanto dinheiro há em \(source.name) agora, sem incluir outras contas ou caixinhas. O app considera os lançamentos existentes para evitar duplicidade.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Informar dinheiro na conta de origem", systemImage: "pencil") {
                                showingSourceSetup = true
                            }
                        }
                    }
                    if accounts.count < 2 {
                        Text("Cadastre pelo menos duas contas ativas em Caixinhas → Gerenciar contas.")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    TextField("Valor em reais", text: $amountText).keyboardType(.decimalPad)
                    DatePicker("Data", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Descrição (opcional)", text: $notes, axis: .vertical).lineLimit(2...4)
                } footer: {
                    Text("O valor sairá da origem e entrará no destino. Receitas e despesas não serão alteradas. Para datas anteriores, o saldo também precisa cobrir os lançamentos posteriores.")
                }
            }
            .navigationTitle("Transferir dinheiro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmar", action: save)
                        .disabled(source == nil || destination == nil || amountText.isEmpty || source?.openingBalanceInCents == nil)
                }
            }
            .onAppear {
                guard !loaded else { return }
                sourceID = initialSourceID
                destinationID = initialDestinationID
                loaded = true
            }
            .sheet(isPresented: $showingSourceSetup) {
                if let sourceID {
                    AccountFormView(accountID: sourceID, requiresCurrentBalance: true)
                }
            }
            .alert("Não foi possível transferir", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        do {
            guard let amount = Money.cents(from: amountText) else { throw FinancialOperationError.invalidAmount }
            guard let source, let destination else { throw FinancialOperationError.differentContext }
            try FinancialOperations.transfer(amountInCents: amount, date: date, from: source,
                                             to: destination, notes: notes, in: context)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Tente novamente. Os campos foram mantidos."
        }
    }
}
