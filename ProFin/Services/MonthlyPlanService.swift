import Foundation
import SwiftData

struct MonthlyAllocation: Identifiable {
    let id: UUID
    let accountID: UUID
    let name: String
    let target: Int64
    let contributed: Int64
    let suggested: Int64
    let explanation: String
}
struct MonthlyPlanResult {
    let available: Int64?
    let pending: Int64
    let remaining: Int64?
    let allocations: [MonthlyAllocation]
    let messages: [String]
}
enum MonthlyPlanError: LocalizedError {
    case invalidValues, duplicateDestination, missingDestination
    var errorDescription: String? {
        switch self {
        case .invalidValues: "Informe valores válidos e uma prioridade entre 1 e 100."
        case .duplicateDestination: "Esta caixinha já tem um destino no plano. Edite a regra existente."
        case .missingDestination: "Escolha uma caixinha ativa."
        }
    }
}

@MainActor
enum MonthlyPlanService {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return "\(parts.year ?? 0)/\(parts.month ?? 0)"
    }
    static func saveSettings(extras: Int64, margin: Int64, now: Date = Date(), in context: ModelContext) throws {
        guard extras >= 0, margin >= 0 else { throw MonthlyPlanError.invalidValues }
        let key = key(for: now)
        let existing = try context.fetch(FetchDescriptor<MonthlyPlanSettings>()).first { $0.key == key }
        let month = try RecurringSchedule.month(containing: now, calendar: .current)
        let settings = existing ?? MonthlyPlanSettings(month: month, key: key, extras: extras, margin: margin)
        if existing == nil { context.insert(settings) }
        settings.extraExpensesInCents = extras; settings.marginInCents = margin
        try FinancialOperations.save(in: context)
    }
    static func saveRule(_ rule: MonthlyAllocationRule? = nil, account: FinancialAccount,
                         amount: Int64, priority: Int, in context: ModelContext) throws {
        guard account.modelContext === context, rule == nil || rule?.modelContext === context else { throw FinancialOperationError.differentContext }
        guard account.isActive, account.kind == .savingsBox else { throw MonthlyPlanError.missingDestination }
        guard amount > 0, (1...100).contains(priority) else { throw MonthlyPlanError.invalidValues }
        let rules = try context.fetch(FetchDescriptor<MonthlyAllocationRule>())
        guard !rules.contains(where: { $0.id != rule?.id && $0.accountID == account.id }) else { throw MonthlyPlanError.duplicateDestination }
        let saved = rule ?? MonthlyAllocationRule(accountID: account.id, amount: amount, priority: priority)
        if rule == nil { context.insert(saved) }
        saved.accountID = account.id; saved.monthlyAmountInCents = amount; saved.priority = priority
        try FinancialOperations.save(in: context)
    }
    static func calculate(accounts: [FinancialAccount], goals: [Goal], rules: [MonthlyAllocationRule],
                          settings: MonthlyPlanSettings?, occurrences: [RecurringExpenseOccurrence],
                          invoices: [CardInvoice], transfers: [AccountTransfer], now: Date = Date(),
                          calendar: Calendar = .current) throws -> MonthlyPlanResult {
        let commitments = try PlanningCommitments.calculate(occurrences: occurrences, invoices: invoices, now: now, calendar: calendar)
        let pending = try FinancialSummary.cents(Decimal(commitments.recurringInCents) + Decimal(commitments.cardInCents))
        var messages = commitments.missing
        let cashAccounts = accounts.filter { $0.isActive && $0.kind != .savingsBox && !$0.isEmergencyReserve }
        let cash = try FinancialSummary.netWorth(accounts: cashAccounts, asOf: now)
        if cash == nil { messages.append("Informe o dinheiro em todas as contas usadas como origem.") }
        if settings?.key != key(for: now, calendar: calendar) { messages.append("Configure os gastos extras e a margem deste mês antes de distribuir dinheiro.") }
        guard let interval = calendar.dateInterval(of: .month, for: now) else { throw FinancialSummaryError.invalidMonth }
        var candidates: [(MonthlyAllocationRule, FinancialAccount, Goal?, Int64)] = []
        for rule in rules.sorted(by: { $0.priority == $1.priority ? $0.id.uuidString < $1.id.uuidString : $0.priority < $1.priority }) {
            guard let account = accounts.first(where: { $0.id == rule.accountID && $0.isActive && $0.kind == .savingsBox }) else { continue }
            let goal = goals.first { !$0.isArchived && $0.savingsAccount?.id == account.id }
            var cap = Int64.max
            if let goal {
                if case .available(_, let remaining, _) = try GoalSummary.progress(for: goal, asOf: now) { cap = remaining }
                else { messages.append("Confira o saldo e o vínculo da meta \(goal.name)."); cap = 0 }
            }
            candidates.append((rule, account, goal, cap))
        }
        let complete = messages.isEmpty
        let free: Int64? = try complete ? cash.map { try FinancialSummary.cents(Decimal($0) - Decimal(pending)
            - Decimal(settings?.extraExpensesInCents ?? 0) - Decimal(settings?.marginInCents ?? 0)) } : nil
        var budget = max(0, free ?? 0)
        var allocations: [MonthlyAllocation] = []
        for (rule, account, goal, cap) in candidates {
            // Aportes já realizados não são renovados por retiradas. Transferências
            // entre caixinhas não representam novo dinheiro destinado neste mês.
            let contributed = try FinancialSummary.cents(transfers.filter {
                $0.destinationAccount.id == account.id && $0.sourceAccount.kind != .savingsBox
                    && $0.date >= interval.start && $0.date < interval.end && $0.date <= now
            }.reduce(Decimal.zero) { $0 + Decimal($1.amountInCents) })
            let desired = max(0, rule.monthlyAmountInCents - min(rule.monthlyAmountInCents, contributed))
            let amount = min(budget, min(desired, cap))
            budget -= amount
            let reason: String
            if !complete { reason = "Complete os dados para receber uma sugestão." }
            else if cap == 0 { reason = "A meta já tem o valor necessário." }
            else if desired == 0 { reason = "O aporte desejado deste mês já foi registrado." }
            else if amount < min(desired, cap) { reason = "O dinheiro livre não cobre todo o aporte desejado após as prioridades anteriores." }
            else { reason = "Sugestão conforme sua prioridade, descontando os aportes já registrados." }
            allocations.append(MonthlyAllocation(id: rule.id, accountID: account.id,
                name: goal.map { "\($0.name) · \(account.name)" } ?? account.name,
                target: rule.monthlyAmountInCents, contributed: contributed, suggested: amount, explanation: reason))
        }
        return MonthlyPlanResult(available: free, pending: pending, remaining: complete ? budget : nil,
                                 allocations: allocations, messages: messages)
    }
}
