import Foundation
import SwiftData

enum AccountOperationError: LocalizedError, Equatable {
    case unknownBalance
    case insufficientBalance(available: Int64)
    case nonzeroBalance
    case missingOpeningBalance

    var errorDescription: String? {
        switch self {
        case .unknownBalance: "Informe quanto dinheiro há na conta antes de continuar."
        case .insufficientBalance(let available):
            "Saldo insuficiente. Disponível para transferência nesta data, considerando também os lançamentos posteriores: \(Money.formatted(max(0, available)))."
        case .nonzeroBalance: "Para desativar a conta, o saldo precisa estar zerado. Transfira o saldo restante ou regularize os lançamentos."
        case .missingOpeningBalance: "Informe quanto dinheiro há na conta agora. Use zero se ela estiver sem dinheiro."
        }
    }
}

extension FinancialOperationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Informe um valor maior que zero."
        case .emptyTitle: "Informe um nome ou descrição."
        case .sameAccount: "Escolha contas diferentes para origem e destino."
        case .futureDate: "A data não pode estar no futuro."
        case .inactiveAccount: "Escolha uma conta ativa."
        case .inactiveCategory: "Escolha uma categoria ativa."
        case .missingClassification: "Escolha a classificação da despesa."
        case .differentContext: "Os dados foram atualizados. Reabra o formulário e tente novamente."
        case .accountHasHistory: "Esta conta tem histórico e não pode ser excluída."
        case .accountHasBalance: "Esta conta tem saldo e não pode ser excluída."
        case .emptyCategoryName: "Informe o nome da categoria."
        case .duplicateCategoryName: "Já existe uma categoria com este nome."
        }
    }
}

extension FinancialOperations {
    @discardableResult
    static func createAccount(name: String, kind: FinancialAccountKind, openingBalanceInCents: Int64,
                              isEmergencyReserve: Bool = false, in context: ModelContext) throws -> FinancialAccount {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinancialOperationError.emptyTitle }
        if isEmergencyReserve && kind != .savingsBox { throw GoalOperationError.protectedReserve }
        let account = FinancialAccount(name: name, kind: kind, openingBalanceInCents: openingBalanceInCents)
        account.isEmergencyReserve = isEmergencyReserve && kind == .savingsBox
        context.insert(account)
        try save(in: context)
        return account
    }

    static func updateAccount(_ account: FinancialAccount, name: String, kind: FinancialAccountKind,
                              openingBalanceInCents: Int64?, isEmergencyReserve: Bool? = nil, in context: ModelContext) throws {
        guard account.modelContext === context else { throw FinancialOperationError.differentContext }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw FinancialOperationError.emptyTitle }
        guard openingBalanceInCents != nil || account.openingBalanceInCents == nil else {
            throw AccountOperationError.missingOpeningBalance
        }
        // Uma conta inativa zerada não deve receber saldo pela edição do valor inicial.
        if !account.isActive && openingBalanceInCents != account.openingBalanceInCents {
            throw FinancialOperationError.inactiveAccount
        }
        let protection = isEmergencyReserve ?? account.isEmergencyReserve
        if protection && kind != .savingsBox { throw GoalOperationError.protectedReserve }
        if protection { try GoalOperations.requireNoActiveGoal(for: account, in: context) }
        if kind != .savingsBox { try GoalOperations.requireNoActiveGoal(for: account, in: context) }
        account.isEmergencyReserve = protection
        account.name = name
        account.kind = kind
        account.openingBalanceInCents = openingBalanceInCents
        try save(in: context)
    }

    static func updateAccountCurrentBalance(_ account: FinancialAccount, name: String, kind: FinancialAccountKind,
                                            currentBalanceInCents: Int64?, isEmergencyReserve: Bool? = nil, in context: ModelContext) throws {
        let opening: Int64?
        if let currentBalanceInCents {
            opening = try FinancialSummary.openingBalance(forCurrentBalance: currentBalanceInCents, of: account)
        } else {
            opening = account.openingBalanceInCents
        }
        try updateAccount(account, name: name, kind: kind, openingBalanceInCents: opening, isEmergencyReserve: isEmergencyReserve, in: context)
    }

    static func setAccountActive(_ account: FinancialAccount, active: Bool, in context: ModelContext) throws {
        guard account.modelContext === context else { throw FinancialOperationError.differentContext }
        if !active {
            try GoalOperations.requireNoActiveGoal(for: account, in: context)
            guard let balance = try FinancialSummary.balance(of: account) else { throw AccountOperationError.unknownBalance }
            guard balance == 0 else { throw AccountOperationError.nonzeroBalance }
        }
        account.isActive = active
        try save(in: context)
    }
}
