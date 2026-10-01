import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct AccountTests {
    private let date = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeAccounts(in context: ModelContext) throws -> (FinancialAccount, FinancialAccount) {
        let checking = FinancialAccount(name: "Conta corrente", kind: .checking, openingBalanceInCents: 200_000)
        let turbo = FinancialAccount(name: "Caixinha Turbo", kind: .turboBox, openingBalanceInCents: 100_000)
        context.insert(checking)
        context.insert(turbo)
        try context.save()
        return (checking, turbo)
    }

    @Test
    func transferPreservesNetWorthAndMonthlyResult() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let (checking, turbo) = try makeAccounts(in: context)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        // A receita e a despesa se compensam no saldo, mas aparecem no mês.
        try FinancialOperations.recordTransaction(
            title: "Recebimento", amountInCents: 5_000, date: date, category: category,
            type: .income, account: checking, classification: .essential, in: context
        )
        try FinancialOperations.recordTransaction(
            title: "Pagamento", amountInCents: 5_000, date: date, category: category,
            type: .expense, account: checking, classification: .essential, in: context
        )
        let before = try FinancialSummary.monthlySummary(
            transactions: context.fetch(FetchDescriptor<FinancialTransaction>()), monthContaining: date
        )

        let transfer = try FinancialOperations.transfer(
            amountInCents: 30_000, date: date, from: checking, to: turbo, in: context
        )

        #expect(try FinancialSummary.balance(of: checking) == 170_000)
        #expect(try FinancialSummary.balance(of: turbo) == 130_000)
        #expect(try FinancialSummary.netWorth(accounts: [checking, turbo]) == 300_000)
        #expect(checking.outgoingTransfers.map(\.id) == [transfer.id])
        #expect(turbo.incomingTransfers.map(\.id) == [transfer.id])
        #expect(checking.incomingTransfers.isEmpty)
        #expect(turbo.outgoingTransfers.isEmpty)
        let transactions = try context.fetch(FetchDescriptor<FinancialTransaction>())
        #expect(transactions.count == 2)
        #expect(transactions.first { $0.type == .income }?.classification == nil)
        #expect(before == MonthlySummary(incomeInCents: 5_000, expenseInCents: 5_000, resultInCents: 0))
        #expect(try FinancialSummary.monthlySummary(transactions: transactions, monthContaining: date) == before)
        #expect(try FinancialSummary.balance(of: checking, asOf: date.addingTimeInterval(-1)) == 200_000)
    }

    @Test
    func unknownOpeningBalanceAndArchivedAccounts() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let initial = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let (checking, turbo) = try makeAccounts(in: context)
        turbo.isActive = false
        try context.save()

        #expect(try FinancialSummary.balance(of: initial) == nil)
        #expect(try FinancialSummary.netWorth(accounts: [initial, checking, turbo]) == nil)
        #expect(try FinancialSummary.netWorth(accounts: [checking, turbo]) == 300_000)
        initial.openingBalanceInCents = 0
        #expect(try FinancialSummary.balance(of: initial) == 0)
        #expect(try FinancialSummary.netWorth(accounts: [initial, checking, turbo]) == 300_000)
    }

    @Test
    func rejectsInvalidOperationsBeforeInsertion() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let (checking, turbo) = try makeAccounts(in: context)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)

        for amount: Int64 in [0, -100] {
            #expect(throws: FinancialOperationError.invalidAmount) {
                try FinancialOperations.transfer(amountInCents: amount, date: date, from: checking, to: turbo, in: context)
            }
            #expect(throws: FinancialOperationError.invalidAmount) {
                try FinancialOperations.recordTransaction(
                    title: "Inválido", amountInCents: amount, date: date, category: category,
                    type: .income, account: checking, in: context
                )
            }
        }
        #expect(throws: FinancialOperationError.sameAccount) {
            try FinancialOperations.transfer(amountInCents: 100, date: date, from: checking, to: checking, in: context)
        }
        #expect(throws: FinancialOperationError.futureDate) {
            try FinancialOperations.transfer(
                amountInCents: 100, date: Date().addingTimeInterval(86_400), from: checking, to: turbo, in: context
            )
        }
        #expect(throws: FinancialOperationError.missingClassification) {
            try FinancialOperations.recordTransaction(
                title: "Despesa", amountInCents: 100, date: date, category: category,
                type: .expense, account: checking, in: context
            )
        }
        turbo.isActive = false
        try context.save()
        #expect(throws: FinancialOperationError.inactiveAccount) {
            try FinancialOperations.transfer(amountInCents: 100, date: date, from: checking, to: turbo, in: context)
        }
        #expect(throws: FinancialOperationError.inactiveAccount) {
            try FinancialOperations.recordTransaction(
                title: "Receita", amountInCents: 100, date: date, category: category,
                type: .income, account: turbo, in: context
            )
        }
        #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(checking.outgoingTransfers.isEmpty)
        #expect(turbo.incomingTransfers.isEmpty)
        #expect(!context.hasChanges)
    }

    @Test
    func preventsDeletionOfAccountsWithEitherSideOfTransferOrTransaction() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let (checking, turbo) = try makeAccounts(in: context)
        let transfer = try FinancialOperations.transfer(
            amountInCents: 30_000, date: date, from: checking, to: turbo, in: context
        )
        for account in [checking, turbo] {
            #expect(throws: FinancialOperationError.accountHasHistory) {
                try FinancialOperations.deleteAccount(account, in: context)
            }
        }
        context.delete(transfer)
        try context.save()
        #expect(checking.outgoingTransfers.isEmpty)
        #expect(turbo.incomingTransfers.isEmpty)
        #expect(try FinancialSummary.balance(of: checking) == 200_000)
        #expect(try FinancialSummary.balance(of: turbo) == 100_000)
        #expect(throws: FinancialOperationError.accountHasBalance) {
            try FinancialOperations.deleteAccount(checking, in: context)
        }
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        try FinancialOperations.recordTransaction(
            title: "Receita", amountInCents: 100, date: date, category: category,
            type: .income, account: checking, in: context
        )
        #expect(throws: FinancialOperationError.accountHasHistory) {
            try FinancialOperations.deleteAccount(checking, in: context)
        }
        turbo.openingBalanceInCents = 0
        try context.save()
        try FinancialOperations.deleteAccount(turbo, in: context)
        #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 1)
    }

    @Test
    func monthlySummaryUsesCalendarBoundaries() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        let start = try #require(calendar.date(from: DateComponents(year: 2025, month: 6, day: 1)))
        let end = try #require(calendar.date(byAdding: .month, value: 1, to: start))
        for (date, amount) in [(start.addingTimeInterval(-1), 10), (start, 20), (end.addingTimeInterval(-1), 30), (end, 40)] {
            try FinancialOperations.recordTransaction(
                title: "Receita", amountInCents: Int64(amount), date: date, category: category,
                type: .income, account: account, in: context
            )
        }
        try FinancialOperations.recordTransaction(
            title: "Despesa", amountInCents: 15, date: start, category: category,
            type: .expense, account: account, classification: .nonEssential, in: context
        )
        #expect(try FinancialSummary.monthlySummary(
            transactions: context.fetch(FetchDescriptor<FinancialTransaction>()),
            monthContaining: start, calendar: calendar
        ) == MonthlySummary(incomeInCents: 50, expenseInCents: 15, resultInCents: 35))
    }

    @Test
    func negativeBalancesAndOverflowAreHandledWithoutWrapping() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        account.openingBalanceInCents = Int64.max
        try context.save()
        let income = try FinancialOperations.recordTransaction(
            title: "Receita", amountInCents: 1, date: date, category: category,
            type: .income, account: account, in: context
        )
        #expect(throws: FinancialSummaryError.amountOverflow) { try FinancialSummary.balance(of: account) }
        try FinancialOperations.recordTransaction(
            title: "Despesa", amountInCents: 1, date: date, category: category,
            type: .expense, account: account, classification: .essential, in: context
        )
        #expect(try FinancialSummary.balance(of: account) == Int64.max)
        account.openingBalanceInCents = 0
        context.delete(income)
        try context.save()
        #expect(try FinancialSummary.balance(of: account) == -1)
    }
}
