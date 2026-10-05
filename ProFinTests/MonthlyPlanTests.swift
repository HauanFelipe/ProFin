import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct MonthlyPlanTests {
    private let calendar = SavingsYieldCalculator.calendar
    private var now: Date { calendar.date(from: DateComponents(year: 2025, month: 7, day: 15))! }

    @Test func prioritiesContributionsGoalCapAndMonthRollover() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let cash = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        cash.openingBalanceInCents = 50_000
        let reserve = FinancialAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: 0)
        reserve.isEmergencyReserve = true
        let box = FinancialAccount(name: "Monitor", kind: .savingsBox, openingBalanceInCents: 9_000)
        context.insert(reserve); context.insert(box)
        let goal = Goal(name: "Monitor", targetAmountInCents: 15_000, savingsAccount: box)
        context.insert(goal)
        try context.save()
        try MonthlyPlanService.saveSettings(extras: 10_000, margin: 10_000, now: now, in: context)
        try MonthlyPlanService.saveRule(account: reserve, amount: 10_000, priority: 1, in: context)
        try MonthlyPlanService.saveRule(account: box, amount: 10_000, priority: 2, in: context)
        #expect(throws: MonthlyPlanError.self) { try MonthlyPlanService.saveRule(account: box, amount: 10_000, priority: 3, in: context) }
        let settings = try #require(context.fetch(FetchDescriptor<MonthlyPlanSettings>()).first)
        let rules = try context.fetch(FetchDescriptor<MonthlyAllocationRule>())
        func calculate(_ date: Date, transfers: [AccountTransfer] = []) throws -> MonthlyPlanResult {
            try MonthlyPlanService.calculate(accounts: [cash, reserve, box], goals: [goal], rules: rules,
                settings: settings, occurrences: [], invoices: [], transfers: transfers, now: date, calendar: calendar)
        }
        let initial = try calculate(now)
        #expect(initial.available == 30_000)
        #expect(initial.allocations.map(\.suggested) == [10_000, 6_000])
        #expect(initial.remaining == 14_000)
        let deposit = AccountTransfer(amountInCents: 4_000, date: now, sourceAccount: cash, destinationAccount: reserve)
        let withdrawal = AccountTransfer(amountInCents: 1_000, date: now, sourceAccount: reserve, destinationAccount: cash)
        context.insert(deposit); context.insert(withdrawal); try context.save()
        let after = try calculate(now, transfers: [deposit, withdrawal])
        #expect(after.available == 27_000)
        #expect(after.allocations.first?.contributed == 4_000)
        #expect(after.allocations.first?.suggested == 6_000)
        cash.openingBalanceInCents = 28_000
        try context.save()
        #expect(try calculate(now, transfers: [deposit, withdrawal]).allocations.map(\.suggested) == [5_000, 0])
        let next = calendar.date(byAdding: .month, value: 1, to: now)!
        #expect(try calculate(next).available == nil)
        #expect(try calculate(next).allocations.allSatisfy { $0.suggested == 0 })
    }

    @Test func missingCashOrSettingsBlocksSuggestionsButUnrelatedUnknownBoxDoesNot() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let cash = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let box = FinancialAccount(name: "Caixinha", kind: .savingsBox)
        context.insert(box)
        try context.save()
        try MonthlyPlanService.saveRule(account: box, amount: 10_000, priority: 1, in: context)
        let rules = try context.fetch(FetchDescriptor<MonthlyAllocationRule>())
        func result(_ settings: MonthlyPlanSettings?) throws -> MonthlyPlanResult {
            try MonthlyPlanService.calculate(accounts: [cash, box], goals: [], rules: rules, settings: settings,
                occurrences: [], invoices: [], transfers: [], now: now, calendar: calendar)
        }
        #expect(try result(nil).available == nil)
        try MonthlyPlanService.saveSettings(extras: 0, margin: 0, now: now, in: context)
        let settings = try #require(context.fetch(FetchDescriptor<MonthlyPlanSettings>()).first)
        #expect(try result(settings).available == nil)
        cash.openingBalanceInCents = 20_000; try context.save()
        #expect(try result(settings).allocations.first?.suggested == 10_000)
    }

    @Test func payingInvoiceDoesNotDeductFreeMoneyTwice() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let cash = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        cash.openingBalanceInCents = 50_000; try context.save()
        try CreditCardService.saveCard(name: "Cartão", limit: 100_000, closingDay: 3, dueDay: 10, in: context)
        let card = try #require(context.fetch(FetchDescriptor<CreditCard>()).first)
        let purchaseDate = calendar.date(from: DateComponents(year: 2025, month: 6, day: 5))!
        _ = try CreditCardService.purchase(card: card, title: "Compra", amount: 20_000, date: purchaseDate,
            category: category, classification: .essential, count: 2, firstMonth: now, calendar: calendar, in: context)
        try MonthlyPlanService.saveSettings(extras: 0, margin: 0, now: now, in: context)
        let settings = try #require(context.fetch(FetchDescriptor<MonthlyPlanSettings>()).first)
        func result() throws -> MonthlyPlanResult {
            try MonthlyPlanService.calculate(accounts: [cash], goals: [], rules: [], settings: settings,
                occurrences: [], invoices: card.invoices, transfers: [], now: now, calendar: calendar)
        }
        #expect(try result().pending == 10_000)
        #expect(try result().available == 40_000)
        let invoice = try #require(card.invoices.sorted { $0.dueDate < $1.dueDate }.first)
        try CreditCardService.pay(invoice, from: cash, date: now, calendar: calendar, in: context)
        #expect(try result().pending == 0)
        #expect(try result().available == 40_000)
        #expect(try CreditCardService.debt(card.invoices) == 10_000)
    }
}
