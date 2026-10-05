import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct CreditCardTests {
    private var calendar: Calendar { SavingsYieldCalculator.calendar }
    private func day(_ year: Int = 2025, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    private func setup() throws -> (ModelContainer, CreditCard, FinancialAccount, ProFin.Category) {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        try CreditCardService.saveCard(name: "Nubank", limit: 500_000, closingDay: 3, dueDay: 10, in: context)
        let card = try #require(context.fetch(FetchDescriptor<CreditCard>()).first)
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        account.openingBalanceInCents = 200_000
        try context.save()
        return (container, card, account, try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first))
    }
    @Test
    func closingBoundaryAndClampedDates() throws {
        let (container, card, _, _) = try setup()
        defer { withExtendedLifetime(container) {} }
        #expect(try CreditCardService.firstMonth(for: day(2025, 6, 2), card: card, calendar: calendar) == day(2025, 6, 1))
        #expect(try CreditCardService.firstMonth(for: day(2025, 6, 3), card: card, calendar: calendar) == day(2025, 7, 1))
        card.closingDay = 25
        #expect(try CreditCardService.firstMonth(for: day(2025, 6, 24), card: card, calendar: calendar) == day(2025, 7, 1))
        #expect(try CreditCardService.firstMonth(for: day(2025, 6, 25), card: card, calendar: calendar) == day(2025, 8, 1))
        let dates = try CreditCardService.dates(month: day(2024, 2, 1), closingDay: 31, dueDay: 31, calendar: calendar)
        #expect(dates.closing == day(2024, 1, 31))
        #expect(dates.due == day(2024, 2, 29))
    }
    @Test
    func installmentsPreserveCentsAndMonthlyTotalsWithoutDebitingCash() throws {
        let (container, card, account, category) = try setup()
        let context = container.mainContext
        let purchase = try CreditCardService.purchase(card: card, title: "Monitor", amount: 10_000,
            date: day(2025, 6, 4), category: category, classification: .nonEssential, count: 3,
            firstMonth: day(2025, 7, 1), calendar: calendar, in: context)
        let items = purchase.installments.sorted { $0.number < $1.number }
        #expect(items.map(\.amountInCents) == [3334, 3333, 3333])
        #expect(card.invoices.count == 3)
        #expect(try FinancialSummary.balance(of: account) == 200_000)
        #expect(try CreditCardService.debt(card.invoices) == 10_000)
        #expect(try FinancialSummary.monthlySummary(transactions: [], monthContaining: day(2025, 7, 1),
            installments: items, calendar: calendar).expenseInCents == 3334)
        #expect(try FinancialSummary.monthlySummary(transactions: [], monthContaining: day(2025, 6, 1),
            installments: items, calendar: calendar).expenseInCents == 0)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
    }
    @Test
    func paymentReducesCashAndDebtOnceAndPreservesNetWorth() throws {
        let (container, card, account, category) = try setup()
        let context = container.mainContext
        let purchase = try CreditCardService.purchase(card: card, title: "Compra", amount: 60_000,
            date: day(2025, 6, 4), category: category, classification: .essential, count: 3,
            firstMonth: day(2025, 7, 1), calendar: calendar, in: context)
        let invoice = try #require(card.invoices.first { calendar.isDate($0.referenceMonth, equalTo: day(2025, 7, 1), toGranularity: .month) })
        let before = try FinancialSummary.balance(of: account)! - CreditCardService.debt(card.invoices)
        try CreditCardService.pay(invoice, from: account, date: day(2025, 7, 10), calendar: calendar, in: context)
        #expect(try FinancialSummary.balance(of: account) == 180_000)
        #expect(try CreditCardService.debt(card.invoices) == 40_000)
        #expect(try FinancialSummary.balance(of: account)! - CreditCardService.debt(card.invoices) == before)
        #expect(try FinancialSummary.balance(of: account, asOf: day(2025, 7, 9)) == 200_000)
        #expect(try FinancialSummary.monthlySummary(transactions: [], monthContaining: day(2025, 7, 1),
            installments: purchase.installments, calendar: calendar).expenseInCents == 20_000)
        #expect(throws: CreditCardError.paidInvoice) { try CreditCardService.pay(invoice, from: account, date: Date(), in: context) }
        #expect(throws: CreditCardError.paidInvoice) { try CreditCardService.deletePurchase(purchase, in: context) }
        #expect(try context.fetchCount(FetchDescriptor<CardInvoicePayment>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(AccountHistory.entries(for: account).first?.amountInCents == 20_000)
        #expect(throws: FinancialOperationError.accountHasHistory) { try FinancialOperations.deleteAccount(account, in: context) }
    }
    @Test
    func rejectsOpenInvoiceAndInsufficientBalanceAndProtectsPaidInvoices() throws {
        let (container, card, account, category) = try setup()
        let context = container.mainContext
        let purchase = try CreditCardService.purchase(card: card, title: "Compra", amount: 30_000,
            date: day(2025, 6, 4), category: category, classification: .essential, count: 1,
            firstMonth: day(2025, 7, 1), calendar: calendar, in: context)
        let invoice = try #require(purchase.installments.first?.invoice)
        #expect(throws: CreditCardError.openInvoice) { try CreditCardService.pay(invoice, from: account, date: day(2025, 7, 2), calendar: calendar, in: context) }
        account.openingBalanceInCents = 10
        try context.save()
        #expect(throws: CreditCardError.insufficientBalance) { try CreditCardService.pay(invoice, from: account, date: day(2025, 7, 10), calendar: calendar, in: context) }
        #expect(invoice.payment == nil)
        #expect(!context.hasChanges)
        account.openingBalanceInCents = 200_000
        try context.save()
        try CreditCardService.pay(invoice, from: account, date: day(2025, 7, 10), calendar: calendar, in: context)
        #expect(throws: CreditCardError.paidInvoice) {
            try CreditCardService.purchase(card: card, title: "Compra antiga", amount: 100,
                date: day(2025, 6, 5), category: category, classification: .essential, count: 1,
                firstMonth: day(2025, 7, 1), calendar: calendar, in: context)
        }
    }
    @Test
    func recurringBillMovesToCardWithoutDuplicatingPendingAndDeletionRestoresIt() throws {
        let (container, card, account, category) = try setup()
        let context = container.mainContext
        let date = day(2025, 6, 2)
        let expense = RecurringExpense(title: "Internet", category: category, expectedAmountInCents: 12_000, dueDay: 10,
            amountType: .fixed, classification: .essential, startMonth: day(2025, 6, 1), createdAt: date)
        context.insert(expense)
        let occurrence = RecurringExpenseOccurrence(expense: expense, month: day(2025, 6, 1), dueDate: day(2025, 6, 10), key: "test")
        context.insert(occurrence); try context.save()
        let purchase = try CreditCardService.purchase(card: card, title: "Internet", amount: 12_000, date: date,
            category: category, classification: .essential, count: 1, firstMonth: day(2025, 6, 1), occurrence: occurrence, calendar: calendar, in: context)
        let pending = try PlanningCommitments.calculate(occurrences: [occurrence], invoices: card.invoices, now: day(2025, 6, 5), calendar: calendar)
        #expect(pending.recurringInCents == 0)
        #expect(pending.cardInCents == 12_000)
        #expect(throws: RecurringExpenseError.alreadyPaid) {
            try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 12_000, date: date, account: account, in: context)
        }
        let charges = try RecurringExpenseSummary.charges(expenses: [expense], occurrences: [occurrence], monthContaining: date, now: date, calendar: calendar)
        #expect(charges.first?.status(asOf: date) == .onCard)
        try CreditCardService.deletePurchase(purchase, in: context)
        #expect(occurrence.cardPurchase == nil)
        #expect(try context.fetchCount(FetchDescriptor<CardInstallment>()) == 0)
        #expect(try PlanningCommitments.calculate(occurrences: [occurrence], invoices: card.invoices, now: date, calendar: calendar).recurringInCents == 12_000)
    }
    @Test
    func cardSettingsChangesDoNotRewriteExistingInvoices() throws {
        let (container, card, _, category) = try setup()
        let context = container.mainContext
        _ = try CreditCardService.purchase(card: card, title: "Uma", amount: 100, date: day(2025, 6, 4), category: category,
            classification: .essential, count: 1, firstMonth: day(2025, 7, 1), calendar: calendar, in: context)
        try CreditCardService.saveCard(card, name: card.name, limit: card.limitInCents, closingDay: 5, dueDay: 15, in: context)
        _ = try CreditCardService.purchase(card: card, title: "Outra", amount: 100, date: day(2025, 6, 5), category: category,
            classification: .essential, count: 1, firstMonth: day(2025, 7, 1), calendar: calendar, in: context)
        #expect(card.invoices.count == 1)
        #expect(card.invoices.first?.dueDate == day(2025, 7, 10))
        #expect(card.invoices.first?.installments.count == 2)
    }
}
