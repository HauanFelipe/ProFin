import Foundation
import SwiftData

enum FinancialOperationError: Error, Equatable {
    case invalidAmount
    case emptyTitle
    case missingClassification
    case inactiveAccount
    case inactiveCategory
    case sameAccount
    case futureDate
    case differentContext
    case accountHasHistory
    case accountHasBalance
    case emptyCategoryName
    case duplicateCategoryName
}

// Ponto de gravação das novas operações. Os Models permitem a hidratação e a
// migração pelo SwiftData; as regras de negócio são verificadas antes da inserção.
@MainActor
enum FinancialOperations {
    @discardableResult
    static func createCategory(name: String, in context: ModelContext) throws -> Category {
        let name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty else { throw FinancialOperationError.emptyCategoryName }
        let categories = try context.fetch(FetchDescriptor<Category>())
        let alreadyExists = categories.contains { category in
            let existing = category.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return existing.compare(name, options: [.caseInsensitive, .diacriticInsensitive],
                                    locale: Locale(identifier: "pt_BR")) == .orderedSame
        }
        guard !alreadyExists else { throw FinancialOperationError.duplicateCategoryName }

        let category = Category(name: name)
        context.insert(category)
        try save(in: context)
        return category
    }

    @discardableResult
    static func recordTransaction(
        title: String,
        amountInCents: Int64,
        date: Date,
        category: Category,
        type: TransactionType,
        account: FinancialAccount,
        classification: ExpenseClassification? = nil,
        notes: String? = nil,
        in context: ModelContext
    ) throws -> FinancialTransaction {
        let transaction = try insertTransaction(
            title: title, amountInCents: amountInCents, date: date, category: category,
            type: type, account: account, classification: classification, notes: notes, in: context
        )
        try save(in: context)
        return transaction
    }

    // Valida e prepara a inserção. O chamador salva junto com os demais vínculos.
    private static func insertTransaction(
        title: String, amountInCents: Int64, date: Date, category: Category,
        type: TransactionType, account: FinancialAccount,
        classification: ExpenseClassification?, notes: String?, in context: ModelContext
    ) throws -> FinancialTransaction {
        try validate(amountInCents: amountInCents, date: date)
        try validate(account: account, in: context)
        guard category.modelContext === context else { throw FinancialOperationError.differentContext }
        guard category.isActive else { throw FinancialOperationError.inactiveCategory }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw FinancialOperationError.emptyTitle }
        guard type != .expense || classification != nil else {
            throw FinancialOperationError.missingClassification
        }

        let transaction = FinancialTransaction(
            title: title, amountInCents: amountInCents, date: date, category: category,
            type: type, account: account, classification: classification, notes: normalized(notes)
        )
        context.insert(transaction)
        return transaction
    }

    @discardableResult
    static func payRecurringExpense(
        _ occurrence: RecurringExpenseOccurrence, amountInCents: Int64,
        date: Date, account: FinancialAccount, notes: String? = nil, in context: ModelContext
    ) throws -> FinancialTransaction {
        guard occurrence.modelContext === context else { throw FinancialOperationError.differentContext }
        guard occurrence.paymentTransaction == nil else { throw RecurringExpenseError.alreadyPaid }
        let transaction = try insertTransaction(
            title: occurrence.title, amountInCents: amountInCents, date: date,
            category: occurrence.category, type: .expense, account: account,
            classification: occurrence.classification, notes: notes, in: context
        )
        occurrence.paymentTransaction = transaction
        try save(in: context)
        return transaction
    }

    static func linkPayment(
        _ transaction: FinancialTransaction, to occurrence: RecurringExpenseOccurrence,
        in context: ModelContext
    ) throws {
        guard occurrence.modelContext === context, transaction.modelContext === context else {
            throw FinancialOperationError.differentContext
        }
        guard occurrence.paymentTransaction == nil else { throw RecurringExpenseError.alreadyPaid }
        guard transaction.type == .expense, transaction.amountInCents > 0,
              transaction.date <= Date(), transaction.account != nil else {
            throw RecurringExpenseError.notAnExpense
        }
        guard transaction.recurringOccurrence == nil else { throw RecurringExpenseError.transactionAlreadyLinked }
        occurrence.paymentTransaction = transaction
        try save(in: context)
    }

    static func deleteTransactions(_ transactions: [FinancialTransaction], in context: ModelContext) throws {
        guard transactions.allSatisfy({ $0.modelContext === context }) else {
            throw FinancialOperationError.differentContext
        }
        for transaction in transactions {
            transaction.recurringOccurrence?.paymentTransaction = nil
            context.delete(transaction)
        }
        try save(in: context)
    }

    @discardableResult
    static func transfer(
        amountInCents: Int64,
        date: Date,
        from source: FinancialAccount,
        to destination: FinancialAccount,
        notes: String? = nil,
        in context: ModelContext
    ) throws -> AccountTransfer {
        try validate(amountInCents: amountInCents, date: date)
        guard source.id != destination.id else { throw FinancialOperationError.sameAccount }
        try validate(account: source, in: context)
        try validate(account: destination, in: context)

        let transfer = AccountTransfer(
            amountInCents: amountInCents, date: date,
            sourceAccount: source, destinationAccount: destination, notes: normalized(notes)
        )
        context.insert(transfer)
        try save(in: context)
        return transfer
    }

    static func deleteAccount(_ account: FinancialAccount, in context: ModelContext) throws {
        guard account.modelContext === context else { throw FinancialOperationError.differentContext }
        guard account.transactions.isEmpty,
              account.outgoingTransfers.isEmpty,
              account.incomingTransfers.isEmpty else {
            throw FinancialOperationError.accountHasHistory
        }
        guard account.openingBalanceInCents == nil || account.openingBalanceInCents == 0 else {
            throw FinancialOperationError.accountHasBalance
        }
        context.delete(account)
        try save(in: context)
    }

    private static func validate(amountInCents: Int64, date: Date) throws {
        guard amountInCents > 0 else { throw FinancialOperationError.invalidAmount }
        guard date <= Date() else { throw FinancialOperationError.futureDate }
    }

    private static func validate(account: FinancialAccount, in context: ModelContext) throws {
        guard account.modelContext === context else { throw FinancialOperationError.differentContext }
        guard account.isActive else { throw FinancialOperationError.inactiveAccount }
    }

    private static func normalized(_ notes: String?) -> String? {
        guard let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else {
            return nil
        }
        return notes
    }

    static func save(in context: ModelContext) throws {
        do {
            try context.save()
        } catch {
            AppData.discardFailedContext(context)
            throw error
        }
    }
}
