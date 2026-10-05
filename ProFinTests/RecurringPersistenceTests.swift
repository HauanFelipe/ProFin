import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct RecurringPersistenceTests {
    private func temporaryStore() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "ProFin.store")
    }

    @Test
    func migratesV2WithoutChangingTransactionsAccountsOrTransfers() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try autoreleasepool {
            let transactionID = UUID()
            let transferID = UUID()
            let accountID = UUID()
            let categoryID = UUID()
            let date = Date(timeIntervalSince1970: 1_750_000_000)
            do {
                let schema = Schema(versionedSchema: ProFinSchemaV2.self)
                let config = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: [config])
                let context = container.mainContext
                context.autosaveEnabled = false
                let checking = ProFinSchemaV2.FinancialAccount(id: accountID, name: "Conta antiga", kind: .checking, openingBalanceInCents: 200_000)
                let savings = ProFinSchemaV2.FinancialAccount(name: "Reserva antiga", kind: .savingsBox, openingBalanceInCents: 100_000)
                let category = ProFinSchemaV2.Category(name: "Categoria antiga")
                category.id = categoryID
                category.isActive = false
                let transaction = ProFinSchemaV2.FinancialTransaction(
                    title: "Despesa antiga", amountInCents: 6500, date: date, category: category,
                    type: .expense, account: checking, classification: .essential, notes: "Preservar"
                )
                transaction.id = transactionID
                let transfer = ProFinSchemaV2.AccountTransfer(amountInCents: 30_000, date: date, sourceAccount: checking, destinationAccount: savings)
                transfer.id = transferID
                context.insert(checking)
                context.insert(savings)
                context.insert(category)
                context.insert(transaction)
                context.insert(transfer)
                try context.save()
            }
            for _ in 0..<2 {
                let container = try AppData.makeContainer(at: url)
                let context = container.mainContext
                let transaction = try #require(context.fetch(FetchDescriptor<FinancialTransaction>()).first)
                let transfer = try #require(context.fetch(FetchDescriptor<AccountTransfer>()).first)
                #expect(transaction.id == transactionID)
                #expect(transaction.category.id == categoryID)
                #expect(transaction.category.name == "Categoria antiga")
                #expect(!transaction.category.isActive)
                #expect(transaction.account?.id == accountID)
                #expect(transaction.notes == "Preservar")
                #expect(transaction.amountInCents == 6500)
                #expect(transaction.classification == .essential)
                #expect(transaction.date == date)
                #expect(transaction.recurringOccurrence == nil)
                #expect(transfer.id == transferID)
                #expect(transfer.amountInCents == 30_000)
                #expect(try FinancialSummary.balance(of: transfer.sourceAccount) == 163_500)
                #expect(try FinancialSummary.balance(of: transfer.destinationAccount) == 130_000)
                #expect(try context.fetchCount(FetchDescriptor<FinancialAccount>()) == 2)
                #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 1)
                #expect(try context.fetchCount(FetchDescriptor<RecurringExpense>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseOccurrence>()) == 0)
            }
        }
    }

    @Test
    func paymentSurvivesReopeningAndDeletionPersistsAsPending() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try autoreleasepool {
            var occurrenceID = UUID()
            var paymentID = UUID()
            do {
                let container = try AppData.makeContainer(at: url)
                let context = container.mainContext
                let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
                let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
                let bill = try RecurringExpenseOperations.create(
                    title: "Internet", category: category, expectedAmountInCents: 12_000, dueDay: 15,
                    amountType: .fixed, classification: .essential, startMonth: Date(), in: context
                )
                let occurrence = try #require(bill.occurrences.first)
                occurrenceID = occurrence.id
                paymentID = try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 12_000, date: Date(), account: account, in: context).id
            }
            do {
                let container = try AppData.makeContainer(at: url)
                let context = container.mainContext
                let occurrence = try #require(context.fetch(FetchDescriptor<RecurringExpenseOccurrence>()).first { $0.id == occurrenceID })
                let payment = try #require(occurrence.paymentTransaction)
                #expect(payment.id == paymentID)
                #expect(payment.recurringOccurrence?.id == occurrenceID)
                #expect(throws: RecurringExpenseError.alreadyPaid) {
                    try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 12_000, date: Date(), account: try #require(payment.account), in: context)
                }
                #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 1)
                try FinancialOperations.deleteTransactions([payment], in: context)
            }
            let reopened = try AppData.makeContainer(at: url)
            let occurrence = try #require(reopened.mainContext.fetch(FetchDescriptor<RecurringExpenseOccurrence>()).first { $0.id == occurrenceID })
            #expect(occurrence.paymentTransaction == nil)
            #expect(occurrence.expectedAmountInCents == 12_000)
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        }
    }

    @Test
    func failedPaymentSaveLeavesNoExpenseOrPaidStatus() throws {
        let url = try temporaryStore()
        // Após uma falha, o SwiftData ainda pode manter descritores SQLite abertos.
        // Este banco isolado fica no diretório temporário até o processo encerrar;
        // removê-lo aqui causaria a exclusão de um arquivo ainda em uso.
        try autoreleasepool {
            do {
                let container = try AppData.makeContainer(at: url)
                let context = container.mainContext
                let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
                try RecurringExpenseOperations.create(title: "Internet", category: category, expectedAmountInCents: 12_000,
                                                     dueDay: 15, amountType: .fixed, classification: .essential,
                                                     startMonth: Date(), in: context)
            }
            do {
                let schema = Schema(versionedSchema: ProFinSchemaV9.self)
                let config = ModelConfiguration("ProFin", schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none)
                let container = try ModelContainer(for: schema, configurations: [config])
                for _ in 0..<2 {
                    let context = AppData.makeContext(for: container)
                    let occurrence = try #require(context.fetch(FetchDescriptor<RecurringExpenseOccurrence>()).first)
                    let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
                    #expect(throws: (any Error).self) {
                        try FinancialOperations.payRecurringExpense(occurrence, amountInCents: 12_000, date: Date(), account: account, in: context)
                    }
                    let fresh = AppData.makeContext(for: container)
                    #expect(try fresh.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
                    #expect(try fresh.fetch(FetchDescriptor<RecurringExpenseOccurrence>()).first?.paymentTransaction == nil)
                }
            }
            let reopened = try AppData.makeContainer(at: url)
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
            #expect(try reopened.mainContext.fetch(FetchDescriptor<RecurringExpenseOccurrence>()).first?.paymentTransaction == nil)
        }
    }

    @Test
    func storePreservesOccurrencesWhenTryingToDeleteTemplateOrCategory() throws {
        let url = try temporaryStore()
        // Após uma falha, o SwiftData ainda pode manter descritores SQLite abertos.
        // Este banco isolado fica no diretório temporário até o processo encerrar;
        // removê-lo aqui causaria a exclusão de um arquivo ainda em uso.
        try autoreleasepool {
            do {
                let container = try AppData.makeContainer(at: url)
                let context = container.mainContext
                let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
                try RecurringExpenseOperations.create(title: "Internet", category: category, expectedAmountInCents: 12_000,
                                                     dueDay: 15, amountType: .fixed, classification: .essential, startMonth: Date(), in: context)
            }
            for deletingCategory in [false, true] {
                let container = try AppData.makeContainer(at: url)
                let context = AppData.makeContext(for: container)
                let bill = try #require(context.fetch(FetchDescriptor<RecurringExpense>()).first)
                if deletingCategory { context.delete(bill.category) } else { context.delete(bill) }
                #expect(throws: (any Error).self) { try context.save() }
                AppData.discardFailedContext(context)
            }
            let reopened = try AppData.makeContainer(at: url)
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<RecurringExpense>()) == 1)
            #expect(try reopened.mainContext.fetchCount(FetchDescriptor<RecurringExpenseOccurrence>()) == 1)
        }
    }
}
