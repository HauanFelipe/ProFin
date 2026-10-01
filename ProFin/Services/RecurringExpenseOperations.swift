import Foundation
import SwiftData

enum RecurringExpenseError: LocalizedError, Equatable {
    case invalidDueDay, missingEstimate, alreadyPaid, transactionAlreadyLinked
    case notAnExpense, invalidStartMonth, missingOccurrence

    var errorDescription: String? {
        switch self {
        case .invalidDueDay: "Escolha um dia de vencimento entre 1 e 31."
        case .missingEstimate: "Informe um valor maior que zero para a conta fixa."
        case .alreadyPaid: "Esta cobrança já foi paga."
        case .transactionAlreadyLinked: "Esta despesa já está vinculada a outra cobrança."
        case .notAnExpense: "Somente uma despesa realizada pode quitar a cobrança."
        case .invalidStartMonth: "A reativação deve começar no mês atual ou em um mês futuro."
        case .missingOccurrence: "A cobrança não está disponível. Reabra a lista e tente novamente."
        }
    }
}

// Operações síncronas no contexto da interface: verificar e inserir não têm pontos de suspensão.
@MainActor
enum RecurringExpenseOperations {
    @discardableResult
    static func create(
        title: String, category: Category, expectedAmountInCents: Int64?, dueDay: Int,
        amountType: RecurringAmountType, classification: ExpenseClassification, startMonth: Date,
        now: Date = Date(), calendar: Calendar = .current, in context: ModelContext
    ) throws -> RecurringExpense {
        try validate(title: title, category: category, amount: expectedAmountInCents,
                     dueDay: dueDay, amountType: amountType, in: context)
        let month = try RecurringSchedule.month(containing: startMonth, calendar: calendar)
        let expense = RecurringExpense(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines), category: category,
            expectedAmountInCents: expectedAmountInCents, dueDay: dueDay, amountType: amountType,
            classification: classification, startMonth: month, createdAt: now
        )
        do {
            context.insert(expense)
            try insertMissingOccurrences(for: expense, through: now, calendar: calendar, in: context)
            try FinancialOperations.save(in: context)
        } catch {
            if context.hasChanges { AppData.discardFailedContext(context) }
            throw error
        }
        return expense
    }

    static func update(
        _ expense: RecurringExpense, title: String, category: Category,
        expectedAmountInCents: Int64?, dueDay: Int, amountType: RecurringAmountType,
        classification: ExpenseClassification, now: Date = Date(), calendar: Calendar = .current,
        in context: ModelContext
    ) throws {
        guard expense.modelContext === context else { throw FinancialOperationError.differentContext }
        try validate(title: title, category: category, amount: expectedAmountInCents,
                     dueDay: dueDay, amountType: amountType, in: context)
        do {
            // Consolidar o passado ANTES de mudar o cadastro, inclusive meses sem abrir o app.
            try insertMissingOccurrences(for: expense, through: now, calendar: calendar, in: context)
            expense.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            expense.category = category
            expense.expectedAmountInCents = expectedAmountInCents
            expense.dueDay = dueDay
            expense.amountType = amountType
            expense.classification = classification
            try FinancialOperations.save(in: context)
        } catch {
            if context.hasChanges { AppData.discardFailedContext(context) }
            throw error
        }
    }

    static func setActive(
        _ expense: RecurringExpense, active: Bool, startingIn: Date? = nil,
        now: Date = Date(), calendar: Calendar = .current, in context: ModelContext
    ) throws {
        guard expense.modelContext === context else { throw FinancialOperationError.differentContext }
        guard expense.isActive != active else { return }
        let currentMonth = try RecurringSchedule.month(containing: now, calendar: calendar)
        let resumeMonth = try RecurringSchedule.month(containing: startingIn ?? now, calendar: calendar)
        guard !active || resumeMonth >= currentMonth else { throw RecurringExpenseError.invalidStartMonth }
        do {
            if active {
                expense.startMonth = resumeMonth
                expense.isActive = true
            }
            try insertMissingOccurrences(for: expense, through: now, calendar: calendar, in: context)
            expense.isActive = active
            try FinancialOperations.save(in: context)
        } catch {
            if context.hasChanges { AppData.discardFailedContext(context) }
            throw error
        }
    }

    static func generateDueOccurrences(
        now: Date = Date(), calendar: Calendar = .current, in context: ModelContext
    ) throws {
        let expenses = try context.fetch(FetchDescriptor<RecurringExpense>())
        do {
            for expense in expenses {
                try insertMissingOccurrences(for: expense, through: now, calendar: calendar, in: context)
            }
            if context.hasChanges { try FinancialOperations.save(in: context) }
        } catch {
            if context.hasChanges { AppData.discardFailedContext(context) }
            throw error
        }
    }

    private static func insertMissingOccurrences(
        for expense: RecurringExpense, through now: Date, calendar: Calendar, in context: ModelContext
    ) throws {
        guard expense.isActive else { return }
        let currentMonth = try RecurringSchedule.month(containing: now, calendar: calendar)
        var month = try RecurringSchedule.month(containing: expense.startMonth, calendar: calendar)
        var keys = Set(expense.occurrences.map(\.occurrenceKey))
        while month <= currentMonth {
            let key = RecurringSchedule.key(expenseID: expense.id, month: month, calendar: calendar)
            if !keys.contains(key) {
                let due = try RecurringSchedule.dueDate(day: expense.dueDay, month: month, calendar: calendar)
                context.insert(RecurringExpenseOccurrence(expense: expense, month: month, dueDate: due, key: key))
                keys.insert(key)
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else {
                throw FinancialSummaryError.invalidMonth
            }
            month = next
        }
    }

    private static func validate(
        title: String, category: Category, amount: Int64?, dueDay: Int,
        amountType: RecurringAmountType, in context: ModelContext
    ) throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinancialOperationError.emptyTitle
        }
        guard category.modelContext === context else { throw FinancialOperationError.differentContext }
        guard category.isActive else { throw FinancialOperationError.inactiveCategory }
        guard (1...31).contains(dueDay) else { throw RecurringExpenseError.invalidDueDay }
        if let amount, amount <= 0 { throw FinancialOperationError.invalidAmount }
        if amountType == .fixed && amount == nil { throw RecurringExpenseError.missingEstimate }
    }
}
