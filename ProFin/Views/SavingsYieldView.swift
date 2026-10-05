import SwiftUI
import SwiftData

struct SavingsYieldView: View {
    let accountID: UUID
    @Query private var accounts: [FinancialAccount]
    @Query private var configurations: [SavingsYieldConfiguration]
    @State private var showingEdit = false

    private var account: FinancialAccount? { accounts.first { $0.id == accountID } }
    private var configuration: SavingsYieldConfiguration? { configurations.first { $0.accountID == accountID } }

    var body: some View {
        List {
            if let account, let configuration {
                Section("Premissas da projeção") {
                    Text(account.name).font(.headline)
                    LabeledContent("Rentabilidade", value: "\(Money.input(Int64(configuration.cdiPercentageBasisPoints)))% do CDI")
                    LabeledContent("CDI anual informado", value: "\(Money.input(Int64(configuration.annualCDIBasisPoints)))%")
                    LabeledContent("Data-base") { Text(configuration.referenceDate, format: .dateTime.day().month().year()) }
                    LabeledContent("Dias de rendimento", value: String(configuration.businessDays))
                }
                if configuration.ledgerSignature != SavingsYieldOperations.ledgerSignature(for: account) {
                    Section {
                        Label("O histórico desta caixinha mudou. Atualize os aportes e os saldos para refazer a projeção.", systemImage: "exclamationmark.triangle")
                    }
                } else if !SavingsYieldCalculator.calendar.isDate(configuration.referenceDate, equalTo: Date(), toGranularity: .month) {
                    Section {
                        Label("Esta projeção é de um mês anterior. Atualize a posição para simular o mês atual.", systemImage: "clock")
                    }
                } else {
                    projection(configuration)
                }
            } else {
                Section {
                    Text("Veja quanto sua caixinha pode render até o fim do mês, com o valor líquido estimado em caso de resgate.")
                    Text("Configure uma posição com os aportes que ainda estão investidos. A simulação usa regras de RDB, CDI constante e os dias de rendimento informados.")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button(configuration == nil ? "Configurar projeção" : "Atualizar projeção") { showingEdit = true }
                    .disabled(account == nil)
            } footer: {
                Text("A previsão não é um rendimento recebido e não altera seu patrimônio registrado. Considere as condições e o vencimento da sua caixinha; a simulação não prevê mudanças da taxa Turbo nem reinvestimentos.")
            }
        }
        .navigationTitle("Rendimento estimado")
        .proFinScreen()
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEdit) { SavingsYieldFormView(accountID: accountID) }
    }

    @ViewBuilder
    private func projection(_ configuration: SavingsYieldConfiguration) -> some View {
        switch Result(catching: {
            try SavingsYieldCalculator.calculate(lots: configuration.lots.map(\.input),
                annualCDIBasisPoints: configuration.annualCDIBasisPoints,
                cdiPercentageBasisPoints: configuration.cdiPercentageBasisPoints,
                referenceDate: configuration.referenceDate, businessDays: configuration.businessDays)
        }) {
        case .success(let result):
            Section("Até o fim do mês") {
                LabeledContent("Data do resgate simulado") { Text(result.redemptionDate, format: .dateTime.day().month().year()) }
                LabeledContent("Principal investido", value: Money.formatted(result.principalInCents))
                LabeledContent("Saldo bruto na data-base", value: Money.formatted(result.initialGrossInCents))
                LabeledContent("Rendimento bruto no período", value: Money.formatted(result.periodYieldInCents))
                LabeledContent("Saldo bruto previsto", value: Money.formatted(result.finalGrossInCents))
            }
            Section {
                LabeledContent("IOF estimado", value: Money.formatted(result.iofInCents))
                LabeledContent("IR estimado", value: Money.formatted(result.incomeTaxInCents))
                LabeledContent("Líquido no resgate", value: Money.formatted(result.finalNetInCents)).fontWeight(.semibold)
            } header: {
                Text("Se resgatar tudo no fim do mês")
            } footer: {
                Text("Os impostos são calculados sobre o rendimento acumulado de cada aporte, incluindo o que já rendeu antes da data-base. Não são descontos mensais automáticos. O IR varia com a idade do aporte; o IOF zera a partir de 30 dias. Estimativa arredondada por aporte, sujeita a diferenças de centavos em relação ao banco.")
            }
        case .failure(let error):
            Section { Text(error.localizedDescription).foregroundStyle(.secondary) }
        }
    }
}
