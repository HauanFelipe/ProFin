import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct TransferRulesTests {
    private let date = Date(timeIntervalSince1970: 1_750_000_000)

    @Test
    func legacyInitialAccountCanTransferAfterExplicitOpeningBalanceSetup() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let source = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        source.name = "Conta inicial"
        source.kind = .other
        let sourceID = source.id
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        try FinancialOperations.recordTransaction(title: "Salário", amountInCents: 200_000,
            date: date, category: category, type: .income, account: source, in: context)
        let box = try FinancialOperations.createAccount(name: "Meta Monitor", kind: .savingsBox,
            openingBalanceInCents: 0, in: context)
        let goal = try GoalOperations.create(name: "Monitor", targetAmountInCents: 180_000, account: box, in: context)
        #expect(throws: AccountOperationError.unknownBalance) {
            try FinancialOperations.transfer(amountInCents: 30_000, date: date, from: source, to: box, in: context)
        }
        // Zero é confirmado pelo usuário, nunca presumido na migração.
        try FinancialOperations.updateAccount(source, name: source.name, kind: source.kind,
            openingBalanceInCents: 0, in: context)
        try FinancialOperations.transfer(amountInCents: 30_000, date: date, from: source, to: box, in: context)
        #expect(source.id == sourceID)
        #expect(source.transactions.count == 1)
        #expect(try FinancialSummary.balance(of: source) == 170_000)
        #expect(try FinancialSummary.balance(of: box) == 30_000)
        #expect(try GoalSummary.progress(for: goal) == .available(balance: 30_000, remaining: 150_000, fraction: 1.0 / 6))
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 1)
        #expect(throws: AccountOperationError.insufficientBalance(available: 170_000)) {
            try FinancialOperations.transfer(amountInCents: 170_001, date: date, from: source, to: box, in: context)
        }
    }

    @Test
    func incomeAndExpenseChangeOnlyTheirAccount() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let source = try FinancialOperations.createAccount(name: "Corrente", kind: .checking, openingBalanceInCents: 0, in: context)
        let box = try FinancialOperations.createAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: 500, in: context)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        try FinancialOperations.recordTransaction(title: "Salário", amountInCents: 250_000, date: date,
            category: category, type: .income, account: source, in: context)
        #expect(try FinancialSummary.balance(of: source) == 250_000)
        try FinancialOperations.recordTransaction(title: "Restaurante", amountInCents: 8_000, date: date,
            category: category, type: .expense, account: source, classification: .nonEssential, in: context)
        #expect(try FinancialSummary.balance(of: source) == 242_000)
        #expect(try FinancialSummary.balance(of: box) == 500)
    }

    @Test
    func rejectsUnknownAndInsufficientBalanceWithoutWriting() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let source = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let box = try FinancialOperations.createAccount(name: "Caixinha", kind: .savingsBox, openingBalanceInCents: 0, in: context)
        #expect(throws: AccountOperationError.unknownBalance) {
            try FinancialOperations.transfer(amountInCents: 1, date: date, from: source, to: box, in: context)
        }
        for opening: Int64 in [-100, 0, 100] {
            source.openingBalanceInCents = opening
            try context.save()
            #expect(throws: AccountOperationError.insufficientBalance(available: opening)) {
                try FinancialOperations.transfer(amountInCents: 101, date: date, from: source, to: box, in: context)
            }
        }
        #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(!context.hasChanges)
        try FinancialOperations.transfer(amountInCents: 100, date: date, from: source, to: box, in: context)
        #expect(try FinancialSummary.balance(of: source) == 0)
        #expect(try FinancialSummary.balance(of: box) == 100)
        try FinancialOperations.transfer(amountInCents: 100, date: date, from: box, to: source, in: context)
        #expect(try FinancialSummary.balance(of: source) == 100)
        #expect(try FinancialSummary.balance(of: box) == 0)
    }

    @Test
    func backdatedTransferCannotSpendLaterIncomeOrCreateLaterDeficit() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let source = try FinancialOperations.createAccount(name: "Corrente", kind: .checking, openingBalanceInCents: 1_000, in: context)
        let box = try FinancialOperations.createAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: 0, in: context)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        try FinancialOperations.recordTransaction(title: "Conta", amountInCents: 800, date: date.addingTimeInterval(100),
            category: category, type: .expense, account: source, classification: .essential, in: context)
        try FinancialOperations.recordTransaction(title: "Receita posterior", amountInCents: 2_000, date: date.addingTimeInterval(200),
            category: category, type: .income, account: source, in: context)
        #expect(try FinancialSummary.balance(of: source) == 2_200)
        #expect(try FinancialSummary.transferableBalance(of: source, on: date) == 200)
        #expect(throws: AccountOperationError.insufficientBalance(available: 200)) {
            try FinancialOperations.transfer(amountInCents: 201, date: date, from: source, to: box, in: context)
        }
        try FinancialOperations.transfer(amountInCents: 200, date: date, from: source, to: box, in: context)
        #expect(try FinancialSummary.balance(of: source, asOf: date.addingTimeInterval(100)) == 0)
        #expect(try FinancialSummary.balance(of: source) == 2_000)
        #expect(try FinancialSummary.netWorth(accounts: [source, box]) == 2_200)
    }

    @Test
    func laterTransfersAlsoLimitBackdatedTransfers() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let source = try FinancialOperations.createAccount(name: "Corrente", kind: .checking, openingBalanceInCents: 1_000, in: context)
        let box = try FinancialOperations.createAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: 0, in: context)
        try FinancialOperations.transfer(amountInCents: 900, date: date.addingTimeInterval(100), from: source, to: box, in: context)
        try FinancialOperations.transfer(amountInCents: 900, date: date.addingTimeInterval(200), from: box, to: source, in: context)
        #expect(try FinancialSummary.transferableBalance(of: source, on: date) == 100)
        #expect(throws: AccountOperationError.insufficientBalance(available: 100)) {
            try FinancialOperations.transfer(amountInCents: 101, date: date, from: source, to: box, in: context)
        }
    }

    @Test
    func historyShowsBothDirectionsAndTransactionsInDateOrder() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let source = try FinancialOperations.createAccount(name: "Nubank", kind: .checking, openingBalanceInCents: 1_000, in: context)
        let box = try FinancialOperations.createAccount(name: "Turbo", kind: .savingsBox, openingBalanceInCents: 0, in: context)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let deposit = try FinancialOperations.transfer(amountInCents: 500, date: date, from: source, to: box, notes: "Reserva", in: context)
        let income = try FinancialOperations.recordTransaction(title: "Receita", amountInCents: 100, date: date.addingTimeInterval(1),
            category: category, type: .income, account: box, in: context)
        let expense = try FinancialOperations.recordTransaction(title: "Despesa", amountInCents: 50, date: date.addingTimeInterval(2),
            category: category, type: .expense, account: box, classification: .essential, in: context)
        let withdrawal = try FinancialOperations.transfer(amountInCents: 200, date: date.addingTimeInterval(3), from: box, to: source, in: context)
        let history = AccountHistory.entries(for: box)
        #expect(history.count == 4)
        #expect(history.map(\.isIncoming) == [false, false, true, true])
        #expect(history.map(\.amountInCents) == [200, 50, 100, 500])
        #expect(history[0].transferID == withdrawal.id)
        #expect(history[1].transactionID == expense.id)
        #expect(history[2].transactionID == income.id)
        #expect(history[3].transferID == deposit.id)
        #expect(history[3].notes == "Reserva")
        #expect(history[3].detail == "De: Nubank")
        #expect(AccountHistory.entries(for: box, asOf: date).count == 1)
        #expect(AccountHistory.entries(for: source).map(\.isIncoming) == [true, false])
        #expect(try FinancialSummary.balance(of: box) == 350)
    }

    @Test
    func deactivateRequiresKnownZeroAndPreservesHistory() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let unknown = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        #expect(throws: AccountOperationError.unknownBalance) {
            try FinancialOperations.setAccountActive(unknown, active: false, in: context)
        }
        let source = try FinancialOperations.createAccount(name: "Origem", kind: .cash, openingBalanceInCents: 100, in: context)
        let box = try FinancialOperations.createAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: 0, in: context)
        #expect(source.createdAt != nil)
        #expect(throws: AccountOperationError.nonzeroBalance) {
            try FinancialOperations.setAccountActive(source, active: false, in: context)
        }
        try FinancialOperations.transfer(amountInCents: 100, date: date, from: source, to: box, in: context)
        try FinancialOperations.setAccountActive(source, active: false, in: context)
        #expect(!source.isActive)
        #expect(source.outgoingTransfers.count == 1)
        #expect(try FinancialSummary.netWorth(accounts: [source, box]) == 100)
        #expect(throws: FinancialOperationError.inactiveAccount) {
            try FinancialOperations.updateAccount(source, name: source.name, kind: .cash, openingBalanceInCents: 200, in: context)
        }
        try FinancialOperations.setAccountActive(source, active: true, in: context)
        #expect(source.isActive)
        #expect(try FinancialSummary.balance(of: source) == 0)
    }

    @Test(arguments: [Int64.min, -123_456, 0, 123_456, Int64.max])
    func openingBalanceInputRoundTrips(_ cents: Int64) {
        #expect(Money.balanceCents(from: Money.input(cents)) == cents)
    }
}
