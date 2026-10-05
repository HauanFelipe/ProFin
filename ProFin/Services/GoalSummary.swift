import Foundation

enum GoalProgress: Equatable {
    case unlinked, unknownBalance, unavailableAccount, archived
    case available(balance: Int64, remaining: Int64, fraction: Double)
}

@MainActor
enum GoalSummary {
    static func progress(for goal: Goal, asOf date: Date = Date()) throws -> GoalProgress {
        guard !goal.isArchived else { return .archived }
        guard let account = goal.savingsAccount else { return .unlinked }
        guard account.isActive, !account.isEmergencyReserve, account.kind == .savingsBox else { return .unavailableAccount }
        guard goal.targetAmountInCents > 0 else { throw GoalOperationError.invalidTarget }
        guard let balance = try FinancialSummary.balance(of: account, asOf: date) else { return .unknownBalance }
        // Um saldo negativo não contribui para a meta; excedentes não passam de 100%.
        let covered = min(max(0, balance), goal.targetAmountInCents)
        return .available(balance: balance, remaining: goal.targetAmountInCents - covered,
                          fraction: Double(covered) / Double(goal.targetAmountInCents))
    }
}
