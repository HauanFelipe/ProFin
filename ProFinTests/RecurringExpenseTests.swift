import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct RecurringExpenseTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return calendar
    }

    private func date(_ month: Int = 6, _ day: Int = 15, year: Int = 2025) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    @discardableResult
    private func create(
        in context: ModelContext, amount: Int64? = 65_000, type: RecurringAmountType = .fixed,
        dueDay: Int = 10, start: Date? = nil, now: Date? = nil
    ) throws -> RecurringExpense {
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        return try RecurringExpenseOperations.create(
            title: "Faculdade", category: category, expectedAmountInCents: amount, dueDay: dueDay,
            amountType: type, classification: .essential, startMonth: start ?? date(6, 1),
            now: now ?? date(), calendar: calendar, in: context
        )
    }

    private func summary(_ context: ModelContext, month: Date? = nil) throws -> RecurringMonthlySummary {
        let month = month ?? date()
        let charges = try RecurringExpenseSummary.charges(
            expenses: context.fetch(FetchDescriptor<RecurringExpense>()),
            occurrences: context.fetch(FetchDescriptor<RecurringExpenseOccurrence>()),
            monthContaining: month, now: date(), calendar: calendar
        )
        return try RecurringExpenseSummary.monthlySummary(
            charges: charges, transactions: context.fetch(FetchDescriptor<FinancialTransaction>()),
            monthContaining: month, calendar: calendar
        )
    }

    @Test
    func fixedExpenseCreatesOnePendingOccurrenceAndNoFinancialTransaction() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = try create(in: context)
        try RecurringExpenseOperations.generateDueOccurrences(now: date(), calendar: calendar, in: context)
        try RecurringExpenseOperations.generateDueOccurrences(now: date(), calendar: calendar, in: context)
        #expect(bill.occurrences.count == 1)
        #expect(bill.frequency == .monthly)
        #expect(bill.isActive)
        #expect(bill.createdAt == date())
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        let totals = try summary(context)
        #expect(totals.expectedInCents == 65_000)
        #expect(totals.pendingInCents == 65_000)
        #expect(totals.paidInCents == 0)
        #expect(totals.committedIncomePercentage == nil)
    }

    @Test
    func variableExpenseUsesActualPaymentAndKeepsOriginalEstimate() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = try create(in: context, amount: 12_000, type: .variable)
        let occurrence = try #require(bill.occurrences.first)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 13_500, date: date(), account: account, in: context)
        let totals = try summary(context)
        #expect(totals.expectedInCents == 12_000)
        #expect(totals.paidInCents == 13_500)
        #expect(totals.pendingInCents == 0)
        #expect(occurrence.expectedAmountInCents == 12_000)
    }

    @Test
    func missingVariableEstimateIsUnknownRatherThanZero() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        try create(in: context)
        let variable = try create(in: context, amount: nil, type: .variable)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        try FinancialOperations.recordTransaction(title: "Salário", amountInCents: 250_000, date: date(),
                                                 category: category, type: .income, account: account, in: context)
        var totals = try summary(context)
        #expect(totals.expectedInCents == nil)
        #expect(totals.pendingInCents == nil)
        #expect(totals.knownPendingInCents == 65_000)
        #expect(totals.missingEstimateCount == 1)
        #expect(totals.committedIncomePercentage == nil)
        try FinancialOperations.payRecurringExpense(try #require(variable.occurrences.first), amountInCents: 5000,
                                                    date: date(), account: account, in: context)
        totals = try summary(context)
        #expect(totals.pendingInCents == 65_000)
        #expect(totals.expectedInCents == nil)
        #expect(totals.paidInCents == 5000)
    }

    @Test
    func paymentIsCountedOnceAndDuplicatePaymentIsRejected() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = try create(in: context)
        let occurrence = try #require(bill.occurrences.first)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        account.openingBalanceInCents = 200_000
        try context.save()
        let payment = try FinancialOperations.payRecurringExpense(
            occurrence, amountInCents: 65_000, date: date(), account: account, in: context
        )
        #expect(payment.recurringOccurrence?.id == occurrence.id)
        #expect(occurrence.paymentTransaction?.id == payment.id)
        #expect(throws: RecurringExpenseError.alreadyPaid) {
            try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 65_000, date: date(), account: account, in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 1)
        #expect(try FinancialSummary.balance(of: account) == 135_000)
        let monthly = try FinancialSummary.monthlySummary(
            transactions: context.fetch(FetchDescriptor<FinancialTransaction>()), monthContaining: date(), calendar: calendar
        )
        #expect(monthly.expenseInCents == 65_000)
        #expect(try summary(context).pendingInCents == 0)
        #expect(!context.hasChanges)
    }

    @Test
    func linksExistingExpenseWithoutCreatingAnotherOrReusingIt() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let first = try #require(create(in: context).occurrences.first)
        let second = try #require(create(in: context).occurrences.first)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let payment = try FinancialOperations.recordTransaction(
            title: "Pago manualmente", amountInCents: 65_000, date: date(), category: first.category,
            type: .expense, account: account, classification: .essential, in: context
        )
        try FinancialOperations.linkPayment(payment, to: first, in: context)
        #expect(throws: RecurringExpenseError.transactionAlreadyLinked) {
            try FinancialOperations.linkPayment(payment, to: second, in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 1)
        #expect(second.paymentTransaction == nil)
        #expect(try summary(context).pendingInCents == 65_000)
        #expect(!context.hasChanges)
    }

    @Test
    func deletionReopensOccurrenceAndRestoresAccountBalance() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let occurrence = try #require(create(in: context).occurrences.first)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        account.openingBalanceInCents = 100_000
        try context.save()
        let payment = try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 65_000,
                                                                 date: date(), account: account, in: context)
        try FinancialOperations.deleteTransactions([payment], in: context)
        #expect(occurrence.paymentTransaction == nil)
        #expect(try summary(context).pendingInCents == 65_000)
        #expect(try FinancialSummary.balance(of: account) == 100_000)
        #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseOccurrence>()) == 1)
    }

    @Test
    func statusesUseCalendarDaysAndPaymentTakesPrecedence() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let occurrence = try #require(create(in: context, dueDay: 20).occurrences.first)
        let charges = try RecurringExpenseSummary.charges(
            expenses: [], occurrences: [occurrence], monthContaining: date(), now: date(), calendar: calendar
        )
        let charge = try #require(charges.first)
        #expect(charge.status(asOf: date(6, 16), calendar: calendar) == .pending)
        #expect(charge.status(asOf: date(6, 17), calendar: calendar) == .dueSoon)
        #expect(charge.status(asOf: date(6, 20), calendar: calendar) == .dueSoon)
        #expect(charge.status(asOf: date(6, 21), calendar: calendar) == .overdue)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 65_000, date: date(6, 21), account: account, in: context)
        let paid = try #require(RecurringExpenseSummary.charges(
            expenses: [], occurrences: [occurrence], monthContaining: date(), now: date(), calendar: calendar
        ).first)
        #expect(paid.status(asOf: date(6, 21), calendar: calendar) == .paid)
    }

    @Test
    func futureMonthIsOnlyAProjectionAndHonorsStartMonth() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = try create(in: context, start: date(8, 1))
        #expect(bill.occurrences.isEmpty)
        let july = try RecurringExpenseSummary.charges(expenses: [bill], occurrences: [], monthContaining: date(7), now: date(), calendar: calendar)
        let august = try RecurringExpenseSummary.charges(expenses: [bill], occurrences: [], monthContaining: date(8), now: date(), calendar: calendar)
        #expect(july.isEmpty)
        #expect(august.count == 1)
        #expect(august.first?.isProjection == true)
        #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseOccurrence>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(!context.hasChanges)
    }

    @Test
    func catchesUpMissingMonthsAndClampsDay31IncludingLeapYear() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = try create(in: context, dueDay: 31, start: date(1, 1, year: 2024), now: date(3, 1, year: 2024))
        #expect(bill.occurrences.count == 3)
        let february = try #require(bill.occurrences.first { calendar.component(.month, from: $0.referenceMonth) == 2 })
        #expect(calendar.component(.day, from: february.dueDate) == 29)
        let due = try RecurringSchedule.dueDate(day: 31, month: date(2), calendar: calendar)
        #expect(calendar.component(.day, from: due) == 28)
        try RecurringExpenseOperations.generateDueOccurrences(now: date(3, 1, year: 2024), calendar: calendar, in: context)
        #expect(bill.occurrences.count == 3)
    }

    @Test
    func editingKeepsHistoricalSnapshotsAndChangesNextMonth() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = try create(in: context, now: date(6, 1))
        try RecurringExpenseOperations.update(bill, title: "Faculdade nova", category: bill.category,
                                             expectedAmountInCents: 70_000, dueDay: 15, amountType: .fixed,
                                             classification: .nonEssential, now: date(8), calendar: calendar, in: context)
        #expect(bill.occurrences.count == 3)
        #expect(bill.occurrences.allSatisfy { $0.expectedAmountInCents == 65_000 && $0.title == "Faculdade" })
        try RecurringExpenseOperations.generateDueOccurrences(now: date(9), calendar: calendar, in: context)
        let september = try #require(bill.occurrences.first { calendar.component(.month, from: $0.referenceMonth) == 9 })
        #expect(september.expectedAmountInCents == 70_000)
        #expect(september.title == "Faculdade nova")
        #expect(september.classification == .nonEssential)
        #expect(calendar.component(.day, from: september.dueDate) == 15)
    }

    @Test
    func deactivationKeepsDebtAndReactivationSkipsInactiveMonths() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = try create(in: context)
        try RecurringExpenseOperations.setActive(bill, active: false, now: date(7), calendar: calendar, in: context)
        #expect(bill.occurrences.count == 2)
        #expect(!bill.isActive)
        try RecurringExpenseOperations.generateDueOccurrences(now: date(9), calendar: calendar, in: context)
        #expect(bill.occurrences.count == 2)
        try RecurringExpenseOperations.setActive(bill, active: true, startingIn: date(10), now: date(9), calendar: calendar, in: context)
        try RecurringExpenseOperations.generateDueOccurrences(now: date(10), calendar: calendar, in: context)
        #expect(Set(bill.occurrences.map { calendar.component(.month, from: $0.referenceMonth) }) == [6, 7, 10])
        #expect(bill.occurrences.allSatisfy { $0.paymentTransaction == nil })
    }

    @Test
    func committedIncomeUsesAllForecastsAndOnlyActualMonthlyIncome() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let bill = try create(in: context, amount: 120_000)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        try FinancialOperations.recordTransaction(title: "Salário", amountInCents: 250_000, date: date(),
                                                 category: bill.category, type: .income, account: account, in: context)
        try FinancialOperations.recordTransaction(title: "Outro mês", amountInCents: 999_999, date: date(5),
                                                 category: bill.category, type: .income, account: account, in: context)
        #expect(try summary(context).committedIncomePercentage == 48)
        try FinancialOperations.payRecurringExpense(try #require(bill.occurrences.first), amountInCents: 120_000,
                                                    date: date(), account: account, in: context)
        #expect(try summary(context).committedIncomePercentage == 48)
        #expect(try summary(context).pendingInCents == 0)
        #expect(RecurringExpenseSummary.committedPercentage(expectedInCents: 300_000, incomeInCents: 250_000) == 120)
        #expect(RecurringExpenseSummary.committedPercentage(expectedInCents: 100, incomeInCents: 0) == nil)
    }

    @Test
    func paymentInAnotherMonthAffectsCashFlowOnlyOnPaymentDate() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let occurrence = try #require(create(in: context).occurrences.first)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 65_000, date: date(7), account: account, in: context)
        let transactions = try context.fetch(FetchDescriptor<FinancialTransaction>())
        #expect(try summary(context).paidInCents == 65_000)
        #expect(try FinancialSummary.monthlySummary(transactions: transactions, monthContaining: date(), calendar: calendar).expenseInCents == 0)
        #expect(try FinancialSummary.monthlySummary(transactions: transactions, monthContaining: date(7), calendar: calendar).expenseInCents == 65_000)
    }

    @Test
    func invalidInputsDoNotCreatePartialRecords() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        #expect(throws: RecurringExpenseError.missingEstimate) { try create(in: context, amount: nil) }
        #expect(throws: FinancialOperationError.invalidAmount) { try create(in: context, amount: 0) }
        #expect(throws: RecurringExpenseError.invalidDueDay) { try create(in: context, dueDay: 32) }
        #expect(try context.fetchCount(FetchDescriptor<RecurringExpense>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseOccurrence>()) == 0)
        let bill = try create(in: context)
        let occurrence = try #require(bill.occurrences.first)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        #expect(throws: FinancialOperationError.invalidAmount) {
            try FinancialOperations.payRecurringExpense(occurrence, amountInCents: -1, date: date(), account: account, in: context)
        }
        #expect(throws: FinancialOperationError.futureDate) {
            try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 100, date: Date().addingTimeInterval(86_400), account: account, in: context)
        }
        let income = try FinancialOperations.recordTransaction(title: "Receita", amountInCents: 100, date: date(),
                                                               category: bill.category, type: .income, account: account, in: context)
        #expect(throws: RecurringExpenseError.notAnExpense) { try FinancialOperations.linkPayment(income, to: occurrence, in: context) }
        #expect(occurrence.paymentTransaction == nil)
        #expect(!context.hasChanges)
    }

    @Test
    func recurringTotalsDetectOverflow() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        try create(in: context, amount: Int64.max)
        try create(in: context, amount: 1)
        #expect(throws: FinancialSummaryError.amountOverflow) { try summary(context) }
    }
}
