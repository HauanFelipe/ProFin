import Foundation
import SwiftData

enum GoalOperationError: LocalizedError, Equatable {
    case invalidName, invalidTarget, invalidAccount, accountAlreadyLinked, accountHasActiveGoal

    var errorDescription: String? {
        switch self {
        case .invalidName: "Informe o nome da meta."
        case .invalidTarget: "O valor da meta precisa ser maior que zero."
        case .invalidAccount: "Escolha uma caixinha ativa ou deixe a meta sem vínculo."
        case .accountAlreadyLinked: "Esta caixinha já está vinculada a outra meta ativa. Escolha outra caixinha ou arquive a meta anterior."
        case .accountHasActiveGoal: "Esta caixinha está vinculada a uma meta ativa. Desvincule ou arquive a meta antes de desativar, excluir ou mudar o tipo da conta."
        }
    }
}

@MainActor
enum GoalOperations {
    @discardableResult
    static func create(name: String, targetAmountInCents: Int64, account: FinancialAccount?,
                       in context: ModelContext) throws -> Goal {
        let name = try validatedName(name, target: targetAmountInCents)
        try validate(account: account, excluding: nil, in: context)
        let goal = Goal(name: name, targetAmountInCents: targetAmountInCents, savingsAccount: account)
        context.insert(goal)
        try FinancialOperations.save(in: context)
        return goal
    }

    static func update(_ goal: Goal, name: String, targetAmountInCents: Int64,
                       account: FinancialAccount?, in context: ModelContext) throws {
        guard goal.modelContext === context else { throw FinancialOperationError.differentContext }
        let name = try validatedName(name, target: targetAmountInCents)
        if !goal.isArchived || account?.id != goal.savingsAccount?.id {
            try validate(account: account, excluding: goal.id, reserve: !goal.isArchived, in: context)
        } else if let account, account.modelContext !== context {
            throw FinancialOperationError.differentContext
        }
        goal.name = name
        goal.targetAmountInCents = targetAmountInCents
        goal.savingsAccount = account
        try FinancialOperations.save(in: context)
    }

    static func setArchived(_ goal: Goal, archived: Bool, in context: ModelContext) throws {
        guard goal.modelContext === context else { throw FinancialOperationError.differentContext }
        if !archived { try validate(account: goal.savingsAccount, excluding: goal.id, in: context) }
        goal.isArchived = archived
        try FinancialOperations.save(in: context)
    }

    static func delete(_ goal: Goal, in context: ModelContext) throws {
        guard goal.modelContext === context else { throw FinancialOperationError.differentContext }
        context.delete(goal)
        try FinancialOperations.save(in: context)
    }

    static func requireNoActiveGoal(for account: FinancialAccount, in context: ModelContext) throws {
        let id = account.id
        let goals = try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { !$0.isArchived }))
        guard !goals.contains(where: { $0.savingsAccount?.id == id }) else { throw GoalOperationError.accountHasActiveGoal }
    }

    private static func validatedName(_ name: String, target: Int64) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GoalOperationError.invalidName }
        guard target > 0 else { throw GoalOperationError.invalidTarget }
        return name
    }

    private static func validate(account: FinancialAccount?, excluding goalID: UUID?, reserve: Bool = true,
                                 in context: ModelContext) throws {
        guard let account else { return }
        guard account.modelContext === context else { throw FinancialOperationError.differentContext }
        guard account.isActive, account.kind == .savingsBox else { throw GoalOperationError.invalidAccount }
        if reserve {
            let goals = try context.fetch(FetchDescriptor<Goal>(predicate: #Predicate { !$0.isArchived }))
            guard !goals.contains(where: { $0.id != goalID && $0.savingsAccount?.id == account.id }) else {
                throw GoalOperationError.accountAlreadyLinked
            }
        }
    }
}
