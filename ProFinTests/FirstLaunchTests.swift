import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct FirstLaunchTests {
    @Test func freshInstallHasNoFinancialHistoryAndReopeningKeepsUserData() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "fresh.store")
        do {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
            #expect(accounts.count == 1)
            let account = try #require(accounts.first)
            #expect(account.name == "Conta Principal")
            #expect(account.openingBalanceInCents == nil)
            #expect(account.kind == .checking)
            #expect(try context.fetchCount(FetchDescriptor<ProFin.Category>()) == 10)
            #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<RecurringExpense>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<RecurringExpenseOccurrence>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CreditCard>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CardPurchase>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CardInvoice>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CardInstallment>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CardInvoicePayment>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<CardRefund>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<SavingsYieldConfiguration>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<SavingsYieldLot>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<MonthlyPlanSettings>()) == 0)
            #expect(try context.fetchCount(FetchDescriptor<MonthlyAllocationRule>()) == 0)
            account.openingBalanceInCents = 12_345
            try context.save()
        }
        let reopened = try AppData.makeContainer(at: url)
        let accounts = try reopened.mainContext.fetch(FetchDescriptor<FinancialAccount>())
        #expect(accounts.count == 1)
        #expect(accounts.first?.openingBalanceInCents == 12_345)
    }
}
