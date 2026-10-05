import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct SpendingAnalysisTests {
    private let calendar = SavingsYieldCalculator.calendar
    private func day(_ month: Int, _ day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: month, day: day))!
    }

    @Test func combinesCardAndCashWithoutCountingIncomePaymentsOrTransfers() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let cash = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        cash.openingBalanceInCents = 100_000
        let food = ProFin.Category(name: "Alimentação")
        let leisure = ProFin.Category(name: "Lazer")
        let old = ProFin.Category(name: "Categoria anterior")
        context.insert(food); context.insert(leisure); context.insert(old)
        func add(_ amount: Int64, _ date: Date, _ category: ProFin.Category,
                 _ classification: ExpenseClassification?, type: TransactionType = .expense) {
            context.insert(FinancialTransaction(title: "Registro", amountInCents: amount, date: date,
                category: category, type: type, account: cash, classification: classification))
        }
        add(10_000, day(7), food, .essential)
        add(2_000, day(7, 31), leisure, .nonEssential)
        add(1_000, day(7, 4), food, nil)
        add(5_000, day(6, 30), food, .essential)
        add(3_000, day(6), old, .essential)
        add(90_000, day(8), food, .essential)
        add(200_000, day(7), food, nil, type: .income)
        try context.save()
        try CreditCardService.saveCard(name: "Cartão", limit: 500_000, closingDay: 3, dueDay: 10, in: context)
        let card = try #require(context.fetch(FetchDescriptor<CreditCard>()).first)
        let purchase = try CreditCardService.purchase(card: card, title: "Compra parcelada", amount: 6_001,
            date: day(6, 5), category: food, classification: .nonEssential, count: 2,
            firstMonth: day(7), calendar: calendar, in: context)
        let invoice = try #require(purchase.installments.first { $0.number == 1 }?.invoice)
        try CreditCardService.pay(invoice, from: cash, date: day(7, 10), calendar: calendar, in: context)
        let box = FinancialAccount(name: "Caixinha", kind: .savingsBox, openingBalanceInCents: 0)
        context.insert(box)
        context.insert(AccountTransfer(amountInCents: 500, date: day(7, 11), sourceAccount: cash, destinationAccount: box))
        try context.save()
        let transactions = try context.fetch(FetchDescriptor<FinancialTransaction>())
        let installments = try context.fetch(FetchDescriptor<CardInstallment>())
        let result = try SpendingAnalysis.calculate(transactions: transactions, installments: installments,
            month: day(7), now: day(8), calendar: calendar)
        #expect(result.total == 16_001)
        #expect(result.previousTotal == 8_000)
        #expect(result.essential == 10_000)
        #expect(result.nonEssential == 5_001)
        #expect(result.unclassified == 1_000)
        #expect(result.categories.first?.name == "Alimentação")
        #expect(result.categories.first?.count == 3)
        #expect(result.largestIncrease?.change == 9_001)
        #expect(abs(result.categories.reduce(0) { $0 + $1.share } - 1) < 0.000001)
        #expect(result.categories.first { $0.id == old.id }?.change == -3_000)
        #expect(result.categories.first { $0.id == leisure.id }?.percentageChange == nil)
        #expect(try FinancialSummary.monthlySummary(transactions: transactions, monthContaining: day(7),
            installments: installments, calendar: calendar).expenseInCents == result.total)
    }

    @Test func emptyMonthAndYearBoundary() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let december = calendar.date(from: DateComponents(year: 2024, month: 12, day: 31))!
        let expense = FinancialTransaction(title: "Anterior", amountInCents: 100, date: december,
            category: category, type: .expense, account: account, classification: .essential)
        context.insert(expense); try context.save()
        let result = try SpendingAnalysis.calculate(transactions: [expense], installments: [], month: day(1), calendar: calendar)
        #expect(result.total == 0)
        #expect(result.previousTotal == 100)
        #expect(result.categories.first?.share == 0)
        #expect(result.categories.first?.percentageChange == -1)
        #expect(result.largestIncrease == nil)
        let empty = try SpendingAnalysis.calculate(transactions: [], installments: [], month: day(1), calendar: calendar)
        #expect(empty.categories.isEmpty)
        #expect(empty.total == 0)
    }

    @Test func overflowingTotalsFailInsteadOfShowingIncorrectAmounts() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let entries = [Int64.max, 1].map { amount in
            FinancialTransaction(title: "Despesa", amountInCents: amount, date: day(7), category: category,
                type: .expense, account: account, classification: .essential)
        }
        for entry in entries { context.insert(entry) }
        #expect(throws: FinancialSummaryError.amountOverflow) {
            try SpendingAnalysis.calculate(transactions: entries, installments: [], month: day(7), calendar: calendar)
        }
    }
}
