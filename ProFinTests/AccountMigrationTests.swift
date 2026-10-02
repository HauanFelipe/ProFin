import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct AccountMigrationTests {
    @Test
    func v3MigrationPreservesPaymentsTransfersAndExistingAccountNames() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "ProFin.store")
        let boxID = UUID()
        let transferID = UUID()
        let paymentID = UUID()
        let expenseID = UUID()
        let occurrenceID = UUID()
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let month = try #require(Calendar.current.dateInterval(of: .month, for: date)?.start)
        try autoreleasepool {
            let schema = Schema(versionedSchema: ProFinSchemaV3.self)
            let config = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            context.autosaveEnabled = false
            let source = ProFinSchemaV3.FinancialAccount(id: AppData.initialAccountID,
                name: "Conta inicial renomeada", kind: .other, openingBalanceInCents: 200_000)
            let box = ProFinSchemaV3.FinancialAccount(id: boxID, name: "Caixinha Turbo", openingBalanceInCents: 100_000)
            box.kindRawValue = "turboBox"
            box.isActive = false // Preservar situações antigas, mesmo fora das novas regras de cadastro.
            let category = ProFinSchemaV3.Category(name: "Educação")
            let recurring = ProFinSchemaV3.RecurringExpense(title: "Faculdade", category: category,
                expectedAmountInCents: 65_000, dueDay: 10, amountType: .fixed, classification: .essential,
                startMonth: month, createdAt: date)
            recurring.id = expenseID
            recurring.isActive = false
            let occurrence = ProFinSchemaV3.RecurringExpenseOccurrence(expense: recurring, month: month,
                dueDate: date, key: "preserved-occurrence")
            occurrence.id = occurrenceID
            let payment = ProFinSchemaV3.FinancialTransaction(title: "Faculdade", amountInCents: 65_000, date: date,
                category: category, type: .expense, account: source, classification: .essential, notes: "Mensalidade")
            payment.id = paymentID
            occurrence.paymentTransaction = payment
            let transfer = ProFinSchemaV3.AccountTransfer(amountInCents: 30_000, date: date,
                sourceAccount: source, destinationAccount: box, notes: "Reserva")
            transfer.id = transferID
            context.insert(source)
            context.insert(box)
            context.insert(category)
            context.insert(recurring)
            context.insert(occurrence)
            context.insert(payment)
            context.insert(transfer)
            try context.save()
        }
        for _ in 0..<2 {
            try autoreleasepool {
                let container = try AppData.makeContainer(at: url)
                let context = container.mainContext
                let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
                #expect(accounts.count == 2)
                let source = try #require(accounts.first { $0.id == AppData.initialAccountID })
                let box = try #require(accounts.first { $0.id == boxID })
                #expect(source.name == "Conta inicial renomeada")
                #expect(source.kind == .other)
                #expect(source.createdAt == nil)
                #expect(box.createdAt == nil)
                #expect(box.name == "Caixinha Turbo")
                #expect(box.kind == .savingsBox)
                #expect(!box.isActive)
                #expect(try FinancialSummary.balance(of: source) == 105_000)
                #expect(try FinancialSummary.balance(of: box) == 130_000)
                #expect(try FinancialSummary.netWorth(accounts: accounts) == 105_000)
                let payments = try context.fetch(FetchDescriptor<FinancialTransaction>())
                #expect(payments.count == 1)
                let payment = try #require(payments.first)
                #expect(payment.id == paymentID)
                #expect(payment.date == date)
                #expect(payment.amountInCents == 65_000)
                #expect(payment.notes == "Mensalidade")
                #expect(payment.recurringOccurrence?.id == occurrenceID)
                #expect(payment.recurringOccurrence?.paymentTransaction?.id == paymentID)
                #expect(payment.recurringOccurrence?.recurringExpense.id == expenseID)
                #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseOccurrence>()) == 1)
                let transfers = try context.fetch(FetchDescriptor<AccountTransfer>())
                #expect(transfers.count == 1)
                #expect(transfers.first?.id == transferID)
                #expect(transfers.first?.date == date)
                #expect(transfers.first?.notes == "Reserva")
                #expect(transfers.first?.sourceAccount.id == source.id)
                #expect(transfers.first?.destinationAccount.id == box.id)
            }
        }
    }
}
