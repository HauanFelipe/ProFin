import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct CardPlanPersistenceTests {
    @Test func cardPaymentsAndPlanSurviveReopening() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "test.store")
        let calendar = SavingsYieldCalculator.calendar
        let date = calendar.date(from: DateComponents(year: 2025, month: 7, day: 15))!
        do {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let cash = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
            let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
            cash.openingBalanceInCents = 100_000
            let box = FinancialAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: 0)
            context.insert(box); try context.save()
            try CreditCardService.saveCard(name: "Cartão", limit: 200_000, closingDay: 3, dueDay: 10, in: context)
            let card = try #require(context.fetch(FetchDescriptor<CreditCard>()).first)
            let purchase = try CreditCardService.purchase(card: card, title: "Compra", amount: 30_001,
                date: calendar.date(byAdding: .month, value: -1, to: date)!, category: category,
                classification: .essential, count: 3, firstMonth: date, calendar: calendar, in: context)
            let invoice = try #require(purchase.installments.first { $0.number == 1 }?.invoice)
            try CreditCardService.pay(invoice, from: cash, date: date, calendar: calendar, in: context)
            try MonthlyPlanService.saveSettings(extras: 1_000, margin: 2_000, now: date, in: context)
            try MonthlyPlanService.saveRule(account: box, amount: 10_000, priority: 1, in: context)
        }
        let reopened = try AppData.makeContainer(at: url)
        let context = reopened.mainContext
        let card = try #require(context.fetch(FetchDescriptor<CreditCard>()).first)
        let payment = try #require(context.fetch(FetchDescriptor<CardInvoicePayment>()).first)
        #expect(card.invoices.count == 3)
        #expect(payment.invoice.payment?.id == payment.id)
        #expect(payment.amountInCents == 10_001)
        #expect(try FinancialSummary.balance(of: payment.account) == 89_999)
        #expect(try CreditCardService.debt(card.invoices) == 20_000)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(try context.fetch(FetchDescriptor<MonthlyPlanSettings>()).first?.marginInCents == 2_000)
        let rule = try #require(context.fetch(FetchDescriptor<MonthlyAllocationRule>()).first)
        #expect(try context.fetch(FetchDescriptor<FinancialAccount>()).contains { $0.id == rule.accountID && $0.name == "Reserva" })
    }

    @Test func versionSevenMigrationPreservesMoneyGoalsAndTransactions() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "test.store")
        do {
            let schema = Schema(versionedSchema: ProFinSchemaV7.self)
            let config = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            let cash = ProFinSchemaV7.FinancialAccount(name: "Minha conta", kind: .checking, openingBalanceInCents: 40_000)
            let box = ProFinSchemaV7.FinancialAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: 10_000)
            box.isEmergencyReserve = true
            let category = ProFinSchemaV7.Category(name: "Compras")
            context.insert(cash); context.insert(box); context.insert(category)
            context.insert(ProFinSchemaV7.FinancialTransaction(title: "Compra anterior", amountInCents: 5_000,
                date: Date(), category: category, type: .expense, account: cash, classification: .essential))
            let goal = ProFinSchemaV7.Goal(name: "Meta antiga", targetAmountInCents: 50_000, savingsAccount: box)
            goal.isArchived = true
            context.insert(goal)
            try context.save()
        }
        let migrated = try AppData.makeContainer(at: url)
        let context = migrated.mainContext
        let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
        let cash = try #require(accounts.first { $0.name == "Minha conta" })
        #expect(accounts.count == 2)
        #expect(try FinancialSummary.balance(of: cash) == 35_000)
        #expect(accounts.first { $0.name == "Reserva" }?.isEmergencyReserve == true)
        let goal = try #require(context.fetch(FetchDescriptor<Goal>()).first)
        #expect(goal.isArchived)
        #expect(goal.savingsAccount?.name == "Reserva")
        #expect(try context.fetchCount(FetchDescriptor<CreditCard>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MonthlyAllocationRule>()) == 0)
    }
}
