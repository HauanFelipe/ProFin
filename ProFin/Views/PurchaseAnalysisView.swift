import SwiftUI
import SwiftData

struct PurchaseAnalysisView: View {
    let goalID: UUID
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var goals: [Goal]
    @Query private var accounts: [FinancialAccount]
    @Query private var occurrences: [RecurringExpenseOccurrence]
    @Query private var transactions: [FinancialTransaction]
    @Query private var invoices: [CardInvoice]
    @State private var purchase = ""
    @State private var extras = "0,00"
    @State private var margin = "0,00"
    @State private var costs = "0,00"
    @State private var now = Date()
    @State private var loaded = false
    @State private var refreshError: String?

    private var goal: Goal? { goals.first { $0.id == goalID } }
    private var result: Result<PurchaseAnalysis, Error> {
        Result {
            guard let goal, let purchaseValue = Money.cents(from: purchase),
                  let extraValue = Money.balanceCents(from: extras), let marginValue = Money.balanceCents(from: margin),
                  let costValue = Money.balanceCents(from: costs) else { throw PurchaseAnalysisError.invalidValues }
            return try PurchaseAnalysisService.analyze(goal: goal, accounts: accounts, occurrences: occurrences,
                transactions: transactions, invoices: invoices, purchaseInCents: purchaseValue, extraExpensesInCents: extraValue,
                marginInCents: marginValue, costsInCents: costValue, now: now)
        }
    }

    var body: some View {
        Form {
            Section {
                moneyField("Valor da compra (R$)", text: $purchase)
                moneyField("Outros gastos previstos (R$)", text: $extras)
                moneyField("Margem a preservar (R$)", text: $margin)
                moneyField("Custos de compra/resgate (R$)", text: $costs)
            } header: {
                Text("Compra à vista hoje")
            } footer: {
                Text("Informe apenas gastos extras ainda não incluídos nas contas pendentes. Custos podem incluir frete ou descontos no resgate da caixinha. A margem é o dinheiro que deseja manter além dos compromissos informados. Esses campos não alteram seus registros.")
            }
            if let refreshError {
                Section {
                    Text(refreshError)
                    Button("Tentar atualizar novamente", action: refresh)
                }
            } else {
                switch result {
                case .success(let analysis):
                    Section("Resultado") {
                        Text(analysis.explanation).font(.headline)
                        ForEach(Array(analysis.missingInformation.enumerated()), id: \.offset) { _, message in
                            Label(message, systemImage: "info.circle").font(.subheadline)
                        }
                    }
                    Section("Como foi calculado") {
                        LabeledContent("Dinheiro fora das caixinhas", value: analysis.cashInCents.map(Money.formatted) ?? "Não informado")
                        LabeledContent("Caixinha desta meta", value: analysis.goalBoxInCents.map(Money.formatted) ?? "Indisponível")
                        LabeledContent("Pendências com valor conhecido", value: Money.formatted(analysis.pendingInCents))
                        Text("Dinheiro nas contas + caixinha da meta − pendências − gastos extras − margem − custos − compra.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let remaining = analysis.remainingInCents {
                            LabeledContent("Sobra após todos os descontos", value: Money.formatted(remaining))
                        }
                    }
                    Section("Faturas incluídas nas pendências") {
                        ForEach(analysis.pendingInvoices) { invoice in
                            NavigationLink { CardInvoiceView(invoiceID: invoice.id) } label: {
                                Text("\(invoice.card.name) · \(invoice.dueDate.formatted(.dateTime.day().month().year().locale(Locale(identifier: "pt_BR"))))")
                            }
                        }
                        LabeledContent("Total em faturas", value: Money.formatted(analysis.cardPendingInCents))
                    }
                    Section("Contas ainda pendentes até o fim do mês") {
                        if analysis.pendingBills.isEmpty { Text("Nenhuma cobrança pendente cadastrada nesse período.") }
                        ForEach(analysis.pendingBills) { bill in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(bill.title)
                                Text(bill.dueDate, format: .dateTime.day().month().year()).font(.caption)
                                Text(bill.expectedAmountInCents.map(Money.formatted) ?? "Sem estimativa")
                            }
                        }
                    }
                    Section {
                        LabeledContent("Receitas realizadas", value: Money.formatted(analysis.monthly.incomeInCents))
                        LabeledContent("Gastos do mês, após estornos", value: Money.formatted(analysis.monthly.expenseInCents))
                        LabeledContent("Resultado do mês", value: Money.formatted(analysis.monthly.resultInCents))
                    } header: {
                        Text("Contexto do mês")
                    } footer: {
                        Text("O resultado inclui parcelas e estornos do mês, mesmo antes do pagamento da fatura. Ele é apenas contexto: o dinheiro livre usa os saldos e as pendências, sem somar o resultado novamente.")
                    }
                case .failure(let error):
                    Section { Text((error as? LocalizedError)?.errorDescription ?? "Não foi possível calcular. Confira os valores informados.") }
                }
            }
            Section {
                Text("A análise cobre os compromissos cadastrados até o fim deste mês, incluindo atrasados. Caixinhas de outras metas, reservas de emergência, receitas futuras e rendimentos projetados ficam fora do cálculo. Não é uma garantia sobre despesas que ainda não foram informadas.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Analisar compra")
        .proFinScreen()
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !loaded, let goal { purchase = Money.input(goal.targetAmountInCents); loaded = true }
            refresh()
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func moneyField(_ title: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("0,00", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }

    private func refresh() {
        now = Date()
        do {
            try RecurringExpenseOperations.generateDueOccurrences(in: context)
            refreshError = nil
        } catch {
            refreshError = "Não foi possível atualizar as contas pendentes. A análise ficará indisponível até concluir essa atualização."
        }
    }
}
