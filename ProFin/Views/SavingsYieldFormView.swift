import SwiftUI
import SwiftData

private struct YieldLotDraft: Identifiable {
    var id = UUID()
    var date = Date()
    var principal = ""
    var gross = ""

    func input() throws -> SavingsYieldLotInput {
        guard let principal = Money.cents(from: principal), let gross = Money.cents(from: gross) else {
            throw SavingsYieldError.invalidLot
        }
        return SavingsYieldLotInput(id: id, applicationDate: date, principalInCents: principal, grossBalanceInCents: gross)
    }
}

struct SavingsYieldFormView: View {
    let accountID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [FinancialAccount]
    @Query private var configurations: [SavingsYieldConfiguration]
    @State private var annualCDI = ""
    @State private var percentage = "100,00"
    @State private var referenceDate = Date()
    @State private var businessDays = SavingsYieldCalculator.suggestedBusinessDays(from: Date())
    @State private var lots: [YieldLotDraft] = [YieldLotDraft()]
    @State private var confirmedRDB = false
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Esta caixinha está aplicada em RDB", isOn: $confirmedRDB)
                } footer: {
                    Text("Confira o investimento no Nubank. Poder resgatar a qualquer momento não identifica sozinho o produto. As regras desta simulação não se aplicam a fundos de investimento.")
                }
                Section("Rentabilidade") {
                    LabeledContent("Percentual do CDI (%)") {
                        TextField("100,00", text: $percentage).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        ForEach([100, 115, 120], id: \.self) { value in
                            Button("\(value)%") { percentage = "\(value),00" }.buttonStyle(.bordered)
                        }
                    }
                    LabeledContent("CDI anual (%)") {
                        TextField("Informe a taxa", text: $annualCDI).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                    }
                    Text("O CDI anual é informado por você. Não há consulta automática. A projeção mantém as duas taxas constantes até o fim do mês.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    DatePicker("Data-base", selection: Binding(
                        get: { referenceDate },
                        set: { referenceDate = $0; businessDays = SavingsYieldCalculator.suggestedBusinessDays(from: $0) }
                    ), in: ...Date(), displayedComponents: .date)
                    Stepper("Dias de rendimento: \(businessDays)", value: $businessDays,
                            in: 0...SavingsYieldCalculator.suggestedBusinessDays(from: referenceDate))
                } footer: {
                    Text("Use a posição no início da data-base. Projetamos até o fim desse mês, sem novos aportes ou retiradas. A sugestão conta segunda a sexta, incluindo a data-base, mas NÃO desconta feriados. Ajuste os dias conforme o calendário de rendimento do banco.")
                }
                Section {
                    Text("Informe separadamente cada aporte que ainda está investido. Use o principal remanescente após retiradas e o saldo BRUTO desse aporte, com os rendimentos já acumulados. Não use o saldo líquido.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Para uma aplicação nova, principal e saldo bruto são iguais. Não sabemos as datas e os ganhos anteriores apenas pelo saldo registrado no ProFin.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach($lots) { $lot in
                    Section("Aporte") {
                        DatePicker("Data da aplicação", selection: $lot.date, in: ...referenceDate, displayedComponents: .date)
                        LabeledContent("Principal (R$)") {
                            TextField("0,00", text: $lot.principal).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Saldo bruto (R$)") {
                            TextField("0,00", text: $lot.gross).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                        }
                        Button("Remover aporte", role: .destructive) { lots.removeAll { $0.id == lot.id } }
                    }
                }
                Button("Adicionar aporte", systemImage: "plus") { lots.append(YieldLotDraft(date: referenceDate)) }
            }
            .navigationTitle("Configurar rendimento")
            .proFinScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar", action: save).disabled(!confirmedRDB) }
            }
            .onAppear(perform: load)
            .alert("Confira os dados", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let saved = configurations.first(where: { $0.accountID == accountID }) else { return }
        annualCDI = Money.input(Int64(saved.annualCDIBasisPoints))
        percentage = Money.input(Int64(saved.cdiPercentageBasisPoints))
        referenceDate = saved.referenceDate
        businessDays = saved.businessDays
        confirmedRDB = true
        lots = saved.lots.sorted { $0.applicationDate < $1.applicationDate }.map {
            YieldLotDraft(id: $0.id, date: $0.applicationDate,
                          principal: Money.input($0.principalInCents), gross: Money.input($0.grossBalanceInCents))
        }
    }

    private func save() {
        do {
            guard let account = accounts.first(where: { $0.id == accountID }) else { throw FinancialOperationError.differentContext }
            guard let annual = Money.balanceCents(from: annualCDI), (0...10_000).contains(annual),
                  let percent = Money.balanceCents(from: percentage), (0...30_000).contains(percent) else {
                throw SavingsYieldError.invalidRates
            }
            try SavingsYieldOperations.save(account: account, lots: lots.map { try $0.input() },
                annualCDIBasisPoints: Int(annual), cdiPercentageBasisPoints: Int(percent),
                referenceDate: referenceDate, businessDays: businessDays, in: context)
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Não foi possível salvar. Os campos foram mantidos."
        }
    }
}
