import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct BackupTests {
    @Test func fullBackupRestoresHistoryRelationshipsAndCanBeExportedAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try AppData.makeContainer(at: folder.appending(path: "original.store"))
        let context = original.mainContext
        let cash = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let calendar = SavingsYieldCalculator.calendar
        let now = calendar.date(from: DateComponents(year: 2025, month: 7, day: 15))!
        cash.openingBalanceInCents = 100_000
        let box = FinancialAccount(name: "Meta", kind: .savingsBox, openingBalanceInCents: 10_000)
        context.insert(box)
        let transfer = AccountTransfer(amountInCents: 5_000, date: now, sourceAccount: cash, destinationAccount: box)
        context.insert(transfer)
        let goal = Goal(name: "Monitor", targetAmountInCents: 50_000, savingsAccount: box)
        context.insert(goal)
        let expense = RecurringExpense(title: "Internet", category: category, expectedAmountInCents: 2_000,
            dueDay: 10, amountType: .fixed, classification: .essential, startMonth: now, createdAt: now)
        expense.isActive = false
        context.insert(expense)
        let occurrence = RecurringExpenseOccurrence(expense: expense, month: now, dueDate: now, key: "backup-test")
        context.insert(occurrence)
        let payment = FinancialTransaction(title: "Internet", amountInCents: 2_000, date: now, category: category,
            type: .expense, account: cash, classification: .essential, notes: "Observação preservada")
        context.insert(payment)
        occurrence.paymentTransaction = payment
        let simulation = SavingsYieldConfiguration(accountID: box.id, annualCDIBasisPoints: 1500,
            cdiPercentageBasisPoints: 12000, referenceDate: now, businessDays: 10, ledgerSignature: "signature")
        simulation.lots = [SavingsYieldLot(input: SavingsYieldLotInput(applicationDate: now, principalInCents: 15_000, grossBalanceInCents: 15_000))]
        context.insert(simulation)
        try context.save()
        try CreditCardService.saveCard(name: "Cartão", limit: 200_000, closingDay: 3, dueDay: 10, in: context)
        let card = try #require(context.fetch(FetchDescriptor<CreditCard>()).first)
        let purchase = try CreditCardService.purchase(card: card, title: "Compra", amount: 30_001,
            date: calendar.date(byAdding: .month, value: -1, to: now)!, category: category,
            classification: .nonEssential, count: 3, firstMonth: now, calendar: calendar, in: context)
        let invoice = try #require(purchase.installments.first { $0.number == 1 }?.invoice)
        try CreditCardService.pay(invoice, from: cash, date: now, calendar: calendar, in: context)
        try MonthlyPlanService.saveSettings(extras: 100, margin: 200, now: now, in: context)
        try MonthlyPlanService.saveRule(account: box, amount: 10_000, priority: 1, in: context)

        // O banco original permanece aberto, com gravações recentes no WAL.
        let data = try BackupService.export(context: context)
        let backup = try BackupService.decode(data)
        #expect(backup.recordCounts.filter { $0.key != "refunds" }.values.allSatisfy { $0 > 0 })
        let restored = try BackupService.prepare(backup, at: folder.appending(path: "restored.store"))
        let restoredContext = restored.mainContext
        let restoredCash = try #require(restoredContext.fetch(FetchDescriptor<FinancialAccount>()).first { $0.id == cash.id })
        #expect(try FinancialSummary.balance(of: restoredCash) == 82_999)
        #expect(try FinancialSummary.balance(of: cash) == 82_999)
        let savedGoal = try #require(restoredContext.fetch(FetchDescriptor<Goal>()).first)
        #expect(savedGoal.savingsAccount?.id == box.id)
        #expect(try FinancialSummary.balance(of: savedGoal.savingsAccount!) == 15_000)
        let savedOccurrence = try #require(restoredContext.fetch(FetchDescriptor<RecurringExpenseOccurrence>()).first)
        #expect(savedOccurrence.paymentTransaction?.id == payment.id)
        #expect(savedOccurrence.paymentTransaction?.notes == "Observação preservada")
        let savedCard = try #require(restoredContext.fetch(FetchDescriptor<CreditCard>()).first)
        #expect(try CreditCardService.debt(savedCard.invoices) == 20_000)
        #expect(savedCard.invoices.contains { $0.payment?.account.id == cash.id })
        #expect(try restoredContext.fetch(FetchDescriptor<SavingsYieldConfiguration>()).first?.lots.count == 1)
        #expect(try restoredContext.fetch(FetchDescriptor<MonthlyAllocationRule>()).first?.accountID == box.id)
        let secondBackup = try BackupService.decode(BackupService.export(context: restoredContext))
        #expect(secondBackup.recordCounts == backup.recordCounts)
        let restoredAgain = try BackupService.prepare(secondBackup, at: folder.appending(path: "again.store"))
        #expect(try restoredAgain.mainContext.fetchCount(FetchDescriptor<AccountTransfer>()) == 1)
    }

    @Test func rejectsCorruptionUnsupportedVersionAndMismatchedCountsWithoutChangingSource() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try AppData.makeContainer(at: folder.appending(path: "source.store"))
        let account = try #require(source.mainContext.fetch(FetchDescriptor<FinancialAccount>()).first)
        account.openingBalanceInCents = 12345
        try source.mainContext.save()
        let backup = try BackupService.decode(BackupService.export(context: source.mainContext))
        let corrupt = ProFinBackup(app: backup.app, formatVersion: 1, schemaVersion: 8,
            createdAt: backup.createdAt, recordCounts: backup.recordCounts, checksum: "invalid", database: backup.database)
        #expect(throws: BackupError.self) { try BackupService.decode(JSONEncoder().encode(corrupt)) }
        let future = ProFinBackup(app: backup.app, formatVersion: 99, schemaVersion: 99,
            createdAt: backup.createdAt, recordCounts: backup.recordCounts, checksum: backup.checksum, database: backup.database)
        #expect(throws: BackupError.self) { try BackupService.decode(JSONEncoder().encode(future)) }
        #expect(throws: BackupError.self) { try BackupService.decode(Data("not a backup".utf8)) }
        let mismatch = ProFinBackup(app: backup.app, formatVersion: 1, schemaVersion: 8,
            createdAt: backup.createdAt, recordCounts: [:], checksum: backup.checksum, database: backup.database)
        #expect(throws: BackupError.self) { try BackupService.prepare(mismatch, at: folder.appending(path: "invalid.store")) }
        let activationDirectory = folder.appending(path: "active")
        let activated = try BackupService.activate(backup, in: activationDirectory)
        let activeURL = try #require(try BackupService.activeStoreURL(in: activationDirectory))
        #expect(try activated.mainContext.fetchCount(FetchDescriptor<FinancialAccount>()) == 1)
        #expect(throws: BackupError.self) { try BackupService.activate(mismatch, in: activationDirectory) }
        #expect(try BackupService.activeStoreURL(in: activationDirectory) == activeURL)
        let reopened = try AppData.makeContainer(at: activeURL)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<FinancialAccount>()).first?.openingBalanceInCents == 12345)
        #expect(try FinancialSummary.balance(of: account) == 12345)
        #expect(try source.mainContext.fetchCount(FetchDescriptor<FinancialAccount>()) == 1)
        account.name = "Alteração não salva"
        #expect(throws: BackupError.self) { try BackupService.export(context: source.mainContext) }
    }
}
