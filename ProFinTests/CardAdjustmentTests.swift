import Foundation
import SwiftData
import Testing
import CryptoKit
import SQLite3
@testable import ProFin

@MainActor
struct CardAdjustmentTests {
    let calendar = SavingsYieldCalculator.calendar
    func day(_ month: Int, _ day: Int = 1) -> Date {
        calendar.date(from: DateComponents(year: 2025, month: month, day: day))!
    }
    func setup() throws -> (ModelContainer, FinancialAccount, CardPurchase) {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        account.openingBalanceInCents = 100_000
        try context.save()
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        try CreditCardService.saveCard(name: "Cartão", limit: 200_000, closingDay: 3, dueDay: 10, in: context)
        let card = try #require(context.fetch(FetchDescriptor<CreditCard>()).first)
        let purchase = try CreditCardService.purchase(card: card, title: "Monitor", amount: 30_000,
            date: day(6, 5), category: category, classification: .nonEssential, count: 3,
            firstMonth: day(7), calendar: calendar, in: context)
        return (container, account, purchase)
    }

    @Test func undoPaymentRestoresCashAndDebtAndCanBeRegisteredAgain() throws {
        let (container, account, purchase) = try setup()
        let context = container.mainContext
        let invoice = try #require(purchase.installments.first { $0.number == 1 }?.invoice)
        try CreditCardService.pay(invoice, from: account, date: day(7, 10), calendar: calendar, in: context)
        #expect(try FinancialSummary.balance(of: account) == 90_000)
        try CreditCardService.undoPayment(invoice, in: context)
        #expect(try FinancialSummary.balance(of: account) == 100_000)
        #expect(try CreditCardService.pending(invoice) == 10_000)
        #expect(try context.fetchCount(FetchDescriptor<CardInvoicePayment>()) == 0)
        #expect(throws: CreditCardError.noPayment) { try CreditCardService.undoPayment(invoice, in: context) }
        try CreditCardService.pay(invoice, from: account, date: day(7, 11), calendar: calendar, in: context)
        #expect(try FinancialSummary.balance(of: account) == 90_000)
        #expect(try context.fetchCount(FetchDescriptor<CardInvoicePayment>()) == 1)
    }

    @Test func refundCarriesAcrossInvoicesWithoutIncomeOrCashAndPaidTimelineIsProtected() throws {
        let (container, account, purchase) = try setup()
        let context = container.mainContext
        let refund = try CreditCardService.refund(purchase: purchase, amount: 25_000, date: day(7, 2),
            month: day(7), calendar: calendar, in: context)
        let invoices = purchase.card.invoices.sorted { $0.referenceMonth < $1.referenceMonth }
        #expect(try CreditCardService.total(invoices[0]) == -15_000)
        #expect(try invoices.map { try CreditCardService.pending($0) } == [0, 0, 5_000])
        #expect(try CreditCardService.debt(invoices) == 5_000)
        #expect(try CreditCardService.creditBalance(invoices) == 0)
        #expect(try FinancialSummary.balance(of: account) == 100_000)
        #expect(try PlanningCommitments.calculate(occurrences: [], invoices: invoices, now: day(7, 5), calendar: calendar).cardInCents == 0)
        let monthly = try FinancialSummary.monthlySummary(transactions: [], monthContaining: day(7),
            installments: purchase.installments, refunds: [refund], calendar: calendar)
        #expect(monthly.incomeInCents == 0)
        #expect(monthly.expenseInCents == -15_000)
        let analysis = try SpendingAnalysis.calculate(transactions: [], installments: purchase.installments,
            month: day(7), refunds: [refund], calendar: calendar)
        #expect(analysis.total == -15_000)
        #expect(analysis.refunded == 25_000)
        #expect(analysis.categories.first?.share == 0)
        #expect(throws: CreditCardError.invalidRefund) {
            try CreditCardService.refund(purchase: purchase, amount: 5_001, date: day(7, 3), month: day(7), calendar: calendar, in: context)
        }
        try CreditCardService.pay(invoices[2], from: account, date: day(9, 10), calendar: calendar, in: context)
        #expect(invoices[2].payment?.amountInCents == 5_000)
        #expect(throws: CreditCardError.laterPaidInvoice) { try CreditCardService.deleteRefund(refund, in: context) }
        try CreditCardService.undoPayment(invoices[2], in: context)
        try CreditCardService.deleteRefund(refund, in: context)
        #expect(try CreditCardService.debt(invoices) == 30_000)
        #expect(try FinancialSummary.balance(of: account) == 100_000)
    }

    @Test func refundOfPaidPurchaseIsCreditNotAvailableCashAndRejectsInvalidValues() throws {
        let (container, account, purchase) = try setup()
        let context = container.mainContext
        for invoice in purchase.card.invoices.sorted(by: { $0.referenceMonth < $1.referenceMonth }) {
            try CreditCardService.pay(invoice, from: account, date: invoice.dueDate, calendar: calendar, in: context)
        }
        #expect(throws: CreditCardError.laterPaidInvoice) {
            try CreditCardService.refund(purchase: purchase, amount: 100, date: day(7, 2), month: day(7), calendar: calendar, in: context)
        }
        for amount: Int64 in [0, -1, 30_001] {
            #expect(throws: CreditCardError.invalidRefund) {
                try CreditCardService.refund(purchase: purchase, amount: amount, date: day(10, 2), month: day(10), calendar: calendar, in: context)
            }
        }
        _ = try CreditCardService.refund(purchase: purchase, amount: 30_000, date: day(10, 2), month: day(10), calendar: calendar, in: context)
        #expect(try CreditCardService.creditBalance(purchase.card.invoices) == 30_000)
        #expect(try CreditCardService.creditBalance(purchase.card.invoices, asOf: day(10)) == 0)
        #expect(try FinancialSummary.balance(of: account) == 70_000)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        let new = try CreditCardService.purchase(card: purchase.card, title: "Outra", amount: 8_000,
            date: day(10, 5), category: purchase.category, classification: .essential, count: 1,
            firstMonth: day(11), calendar: calendar, in: context)
        #expect(try CreditCardService.pending(new.installments[0].invoice) == 0)
        #expect(try CreditCardService.creditBalance(purchase.card.invoices) == 22_000)
    }

    @Test func oldBackupMigratesAndNewRefundSurvivesBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "old.store")
        do {
            let schema = Schema(versionedSchema: ProFinSchemaV8.self)
            let config = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let account = ProFinSchemaV8.FinancialAccount(name: "Conta", kind: .checking, openingBalanceInCents: 99_000)
            let category = ProFinSchemaV8.Category(name: "Categoria")
            container.mainContext.insert(account); container.mainContext.insert(category)
            try container.mainContext.save()
        }
        var sqlite: OpaquePointer?
        #expect(sqlite3_open(url.path, &sqlite) == SQLITE_OK)
        #expect(sqlite3_exec(sqlite, "PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(sqlite)
        let data = try Data(contentsOf: url)
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let counts = ["accounts": 1, "categories": 1, "transactions": 0, "transfers": 0,
            "recurringExpenses": 0, "occurrences": 0, "yieldConfigurations": 0, "yieldLots": 0,
            "goals": 0, "cards": 0, "purchases": 0, "installments": 0, "invoices": 0,
            "payments": 0, "monthlySettings": 0, "allocationRules": 0]
        let oldBackup = ProFinBackup(app: "ProFin", formatVersion: 1, schemaVersion: 8, createdAt: Date(), recordCounts: counts, checksum: checksum, database: data)
        let restored = try BackupService.prepare(oldBackup, at: folder.appending(path: "migrated.store"))
        let context = restored.mainContext
        #expect(try context.fetch(FetchDescriptor<FinancialAccount>()).first?.openingBalanceInCents == 99_000)
        try CreditCardService.saveCard(name: "Card", limit: 100_000, closingDay: 3, dueDay: 10, in: context)
        let card = try #require(context.fetch(FetchDescriptor<CreditCard>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let purchase = try CreditCardService.purchase(card: card, title: "Compra", amount: 5_000, date: day(6, 5), category: category,
            classification: .essential, count: 1, firstMonth: day(7), calendar: calendar, in: context)
        _ = try CreditCardService.refund(purchase: purchase, amount: 3_000, date: day(7, 2), month: day(7), calendar: calendar, in: context)
        let backup = try BackupService.decode(BackupService.export(context: context))
        #expect(backup.schemaVersion == 9)
        let reopened = try BackupService.prepare(backup, at: folder.appending(path: "reopened.store"))
        let refund = try #require(reopened.mainContext.fetch(FetchDescriptor<CardRefund>()).first)
        #expect(refund.purchase.id == purchase.id)
        #expect(refund.invoice.refunds.count == 1)
        #expect(try CreditCardService.pending(refund.invoice) == 2_000)
    }
}
