import SwiftUI
import SwiftData

struct DashboardPlanningSections: View {
    let now: Date
    let refreshed: Bool
    let retry: () -> Void
    @Query private var accounts: [FinancialAccount]
    @Query private var goals: [Goal]
    @Query private var rules: [MonthlyAllocationRule]
    @Query private var settings: [MonthlyPlanSettings]
    @Query private var occurrences: [RecurringExpenseOccurrence]
    @Query private var invoices: [CardInvoice]
    @Query private var transfers: [AccountTransfer]

    private var plan: Result<MonthlyPlanResult, Error> {
        Result { try MonthlyPlanService.calculate(accounts: accounts, goals: goals, rules: rules,
            settings: settings.first { $0.key == MonthlyPlanService.key(for: now) },
            occurrences: occurrences, invoices: invoices, transfers: transfers, now: now) }
    }

    private struct DueItem: Identifiable {
        let id: String
        let title: String
        let date: Date
        let amount: Int64?
        let invoiceID: UUID?
    }
    private func dueItems(_ commitments: PlanningCommitments) throws -> [DueItem] {
        let bills = commitments.recurring.map {
            DueItem(id: "bill/\($0.id)", title: $0.title, date: $0.dueDate,
                    amount: $0.expectedAmountInCents, invoiceID: nil)
        }
        let cards = try commitments.invoices.map {
            DueItem(id: "card/\($0.id)", title: "Fatura · \($0.card.name)", date: $0.dueDate,
                    amount: try CreditCardService.pending($0, asOf: now), invoiceID: $0.id)
        }
        return (bills + cards).sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    var body: some View {
        if !refreshed {
            Section("Planejamento indisponível") {
                Text("Não foi possível atualizar as contas pendentes.")
                Button("Tentar novamente", action: retry)
            }
        } else {
            switch plan {
            case .success(let plan):
                Section {
                    Text(plan.available.map(Money.formatted) ?? "Cálculo incompleto")
                        .font(.title2.bold())
                    if plan.messages.isEmpty {
                        LabeledContent("Contas e faturas pendentes", value: Money.formatted(plan.pending))
                    }
                    if let available = plan.available, available < 0 {
                        Text("Os compromissos e a margem superam o dinheiro disponível.")
                            .foregroundStyle(.red)
                    }
                    ForEach(Array(plan.messages.enumerated()), id: \.offset) { _, message in
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                    NavigationLink("Conferir Plano do mês") { MonthlyPlanView() }
                } header: {
                    Text("Dinheiro livre neste mês")
                } footer: {
                    Text("Dinheiro fora das caixinhas menos contas e faturas pendentes até o fim do mês, gastos extras e margem. Inclui atrasados. As sugestões de aporte ainda não foram descontadas.")
                }
                Section("Sugestões do Plano do mês") {
                    if plan.available == nil {
                        Text("Complete os dados no Plano do mês para receber sugestões.")
                    } else if plan.allocations.isEmpty {
                        Text("Adicione caixinhas ou metas ao Plano do mês e escolha quanto deseja guardar.")
                    } else {
                        ForEach(plan.allocations.filter { $0.suggested > 0 }.prefix(3)) { allocation in
                            LabeledContent(allocation.name, value: Money.formatted(allocation.suggested))
                        }
                        if !plan.allocations.contains(where: { $0.suggested > 0 }) {
                            Text("Nenhum aporte sugerido agora. Confira no plano os saldos, prioridades e valores já destinados.")
                        }
                        if let remaining = plan.remaining {
                            LabeledContent("Livre após todas as sugestões", value: Money.formatted(remaining))
                        }
                    }
                    NavigationLink("Ver sugestões e registrar aportes") { MonthlyPlanView() }
                }
            case .failure:
                Section("Plano do mês") {
                    Text("Não foi possível calcular o planejamento. Confira seus valores.")
                    NavigationLink("Abrir plano") { MonthlyPlanView() }
                }
            }
            Section {
                switch Result(catching: { try dueItems(PlanningCommitments.calculate(
                    occurrences: occurrences, invoices: invoices, now: now
                )) }) {
                case .success(let items):
                    if items.isEmpty { Text("Nenhuma conta ou fatura pendente até o fim do mês.") }
                    ForEach(items.prefix(5)) { item in
                        NavigationLink {
                            if let id = item.invoiceID { CardInvoiceView(invoiceID: id) }
                            else { RecurringExpensesView() }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent(item.title, value: item.amount.map(Money.formatted) ?? "Sem estimativa")
                                Text(item.date, format: .dateTime.day().month(.wide).year())
                                    .font(.caption)
                                if Calendar.current.startOfDay(for: item.date) < Calendar.current.startOfDay(for: now) {
                                    Text("Atrasado").font(.caption).foregroundStyle(.red)
                                } else if Calendar.current.isDate(item.date, inSameDayAs: now) {
                                    Text("Vence hoje").font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                    }
                case .failure:
                    Text("Não foi possível consultar os vencimentos.")
                }
                NavigationLink("Todas as contas recorrentes") { RecurringExpensesView() }
                NavigationLink("Cartões e faturas") { CreditCardsView() }
            } header: {
                Text("Pendências e próximos vencimentos")
            } footer: {
                Text("Até cinco pendências com vencimento até o fim do mês, começando pelas mais antigas. Recorrências lançadas no cartão aparecem na fatura.")
            }
        }
    }
}
