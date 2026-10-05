import SwiftUI
import SwiftData

struct MonthlyPlanView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var accounts: [FinancialAccount]
    @Query private var goals: [Goal]
    @Query private var rules: [MonthlyAllocationRule]
    @Query private var settings: [MonthlyPlanSettings]
    @Query private var occurrences: [RecurringExpenseOccurrence]
    @Query private var invoices: [CardInvoice]
    @Query private var transfers: [AccountTransfer]
    @State private var now = Date()
    @State private var editSettings = false
    @State private var editRule = false
    @State private var selectedRuleID: UUID?
    @State private var selectedTransfer: TransferSuggestion?
    @State private var error: String?
    @State private var refreshFailed = false
    private struct TransferSuggestion: Identifiable { let id: UUID; let amount: Int64 }
    private var monthSettings: MonthlyPlanSettings? { settings.first { $0.key == MonthlyPlanService.key(for: now) } }
    private var result: Result<MonthlyPlanResult, Error> {
        Result { try MonthlyPlanService.calculate(accounts: accounts, goals: goals, rules: rules,
            settings: monthSettings, occurrences: occurrences, invoices: invoices, transfers: transfers, now: now) }
    }
    var body: some View {
        List {
            Section {
                ProFinIntro(title: "Quanto guardar este mês?", message: "Confira as contas, defina uma margem e escolha suas prioridades.", symbol: "calendar")
                Text(now, format: .dateTime.month(.wide).year()).font(.headline)
                Button("1. Definir gastos extras e margem") { editSettings = true }
                if let settings = monthSettings {
                    LabeledContent("Outros gastos previstos", value: Money.formatted(settings.extraExpensesInCents))
                    LabeledContent("Margem a manter", value: Money.formatted(settings.marginInCents))
                }
            }
            if refreshFailed {
                Section { Text("Não foi possível atualizar as pendências."); Button("Tentar novamente", action: refresh) }
            } else {
                switch result {
                case .success(let plan):
                    Section("Dinheiro livre para destinar") {
                        Text(plan.available.map(Money.formatted) ?? "Cálculo incompleto").font(.title2.bold())
                        LabeledContent("Contas e faturas pendentes", value: Money.formatted(plan.pending))
                        if let free = plan.available, free < 0 {
                            Text("Os compromissos e a margem superam o dinheiro disponível. Não há sugestão de aporte neste momento.")
                        }
                        ForEach(Array(plan.messages.enumerated()), id: \.offset) { _, message in Text(message).foregroundStyle(.secondary) }
                    }
                    Section("Suas sugestões de aporte") {
                        ForEach(plan.allocations) { allocation in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(allocation.name).font(.headline)
                                Text("Desejado: \(Money.formatted(allocation.target)) · Já destinado: \(Money.formatted(allocation.contributed))")
                                Text("Destine agora: \(Money.formatted(allocation.suggested))").fontWeight(.semibold)
                                Text(allocation.explanation).font(.footnote).foregroundStyle(.secondary)
                                if allocation.suggested > 0 {
                                    Button("Registrar transferência") { selectedTransfer = TransferSuggestion(id: allocation.accountID, amount: allocation.suggested) }
                                }
                            }.padding(.vertical, 4)
                        }
                        if let remaining = plan.remaining {
                            LabeledContent("Livre após as sugestões", value: Money.formatted(remaining))
                        }
                    }
                case .failure:
                    Text("Não foi possível calcular o plano. Confira os valores e os saldos.")
                }
            }
            Section("2. Escolha onde guardar") {
                ForEach(rules.sorted { $0.priority < $1.priority }) { rule in
                    Button {
                        selectedRuleID = rule.id; editRule = true
                    } label: {
                        VStack(alignment: .leading) {
                            Text("\(rule.priority). \(accounts.first { $0.id == rule.accountID }?.name ?? "Conta removida")")
                            Text("\(Money.formatted(rule.monthlyAmountInCents)) por mês").font(.subheadline)
                            if !accounts.contains(where: { $0.id == rule.accountID && $0.isActive && $0.kind == .savingsBox }) {
                                Text("Destino indisponível · sem sugestão").font(.caption)
                            }
                        }
                    }
                }
                Button("Adicionar caixinha ou meta", systemImage: "plus") { selectedRuleID = nil; editRule = true }
            }
            Section {
                Text("O plano usa o dinheiro fora das caixinhas, menos pendências até o fim do mês, gastos extras e margem. A ordem e os valores são escolhidos por você; cada meta usa a própria caixinha, sem duplicação. Menor número significa maior prioridade.")
                Text("Aportes já registrados de contas para caixinhas são abatidos da intenção mensal. Retiradas não renovam essa intenção. Os destinos se repetem nos próximos meses, mas gastos extras e margem precisam ser confirmados a cada mês.")
                Text("Nada é transferido pelo app. Registre somente o que você realizou no banco. Não há previsão de receitas futuras ou de rendimentos no dinheiro livre.")
            }.font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Plano do mês")
        .proFinScreen()
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
        .sheet(isPresented: $editSettings, onDismiss: refresh) { MonthlyPlanSettingsView() }
        .sheet(isPresented: $editRule, onDismiss: refresh) { MonthlyPlanRuleView(ruleID: selectedRuleID) }
        .sheet(item: $selectedTransfer, onDismiss: refresh) { suggestion in
            TransferFormView(initialDestinationID: suggestion.id, initialAmountInCents: suggestion.amount)
        }
    }
    private func refresh() {
        now = Date()
        do { try RecurringExpenseOperations.generateDueOccurrences(in: context); refreshFailed = false }
        catch { refreshFailed = true }
    }
}

private struct MonthlyPlanSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settings: [MonthlyPlanSettings]
    @State private var extras = "0,00"
    @State private var margin = "0,00"
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Gastos extras (R$)") { TextField("0,00", text: $extras).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                LabeledContent("Margem a manter (R$)") { TextField("0,00", text: $margin).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                Text("Informe apenas gastos que ainda não estão nas contas recorrentes ou faturas pendentes. Atualize essa estimativa quando registrar esses gastos, para não reservar o mesmo valor duas vezes. Use zero se não houver valores adicionais.").font(.footnote)
            }
            .navigationTitle("Planejar este mês")
            .proFinScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") {
                    do {
                        guard let extra = Money.balanceCents(from: extras), let margin = Money.balanceCents(from: margin) else { throw MonthlyPlanError.invalidValues }
                        try MonthlyPlanService.saveSettings(extras: extra, margin: margin, in: context); dismiss()
                    } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Tente novamente." }
                } }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let settings = settings.first(where: { $0.key == MonthlyPlanService.key(for: Date()) }) {
                    extras = Money.input(settings.extraExpensesInCents); margin = Money.input(settings.marginInCents)
                }
            }
            .alert("Confira os valores", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}

private struct MonthlyPlanRuleView: View {
    let ruleID: UUID?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var rules: [MonthlyAllocationRule]
    @Query(sort: \FinancialAccount.name) private var accounts: [FinancialAccount]
    @Query private var goals: [Goal]
    @State private var accountID: UUID?
    @State private var amount = ""
    @State private var priority = 1
    @State private var loaded = false
    @State private var error: String?
    private var rule: MonthlyAllocationRule? { rules.first { $0.id == ruleID } }
    var body: some View {
        NavigationStack {
            Form {
                Picker("Caixinha ou meta", selection: $accountID) {
                    Text("Selecione").tag(nil as UUID?)
                    ForEach(accounts.filter { ($0.isActive && $0.kind == .savingsBox) || $0.id == rule?.accountID }) { account in
                        let goal = goals.first { !$0.isArchived && $0.savingsAccount?.id == account.id }
                        Text(goal.map { "\($0.name) · \(account.name)" } ?? account.name).tag(Optional(account.id))
                    }
                }
                TextField("Quanto deseja guardar por mês (R$)", text: $amount).keyboardType(.decimalPad)
                Stepper("Prioridade: \(priority)", value: $priority, in: 1...100)
                Text("O plano atende primeiro os menores números. Cada caixinha pode aparecer uma única vez. Metas que já atingiram o valor deixam de receber sugestões.").font(.footnote)
                if let rule {
                    Button("Remover do plano", role: .destructive) {
                        do { context.delete(rule); try FinancialOperations.save(in: context); dismiss() }
                        catch { self.error = "Não foi possível remover. Tente novamente." }
                    }
                }
            }
            .navigationTitle("Destino do plano")
            .proFinScreen()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") {
                    do {
                        guard let account = accounts.first(where: { $0.id == accountID }), let amount = Money.cents(from: amount) else { throw MonthlyPlanError.invalidValues }
                        if ruleID != nil && rule == nil { throw FinancialOperationError.differentContext }
                        try MonthlyPlanService.saveRule(rule, account: account, amount: amount, priority: priority, in: context); dismiss()
                    } catch { self.error = (error as? LocalizedError)?.errorDescription ?? "Tente novamente." }
                } }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                if let rule { accountID = rule.accountID; amount = Money.input(rule.monthlyAmountInCents); priority = rule.priority }
            }
            .alert("Não foi possível salvar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }
}
