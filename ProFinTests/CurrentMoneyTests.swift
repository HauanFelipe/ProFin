import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct CurrentMoneyTests {
    @Test
    func settingCurrentMoneyDoesNotDoubleCountExistingIncomeExpensesOrTransfers() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let box = try FinancialOperations.createAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: 100_000, in: context)
        try FinancialOperations.recordTransaction(title: "Salário", amountInCents: 250_000, date: Date(), category: category, type: .income, account: account, in: context)
        try FinancialOperations.recordTransaction(title: "Conta", amountInCents: 50_000, date: Date(), category: category, type: .expense, account: account, classification: .essential, in: context)
        try FinancialOperations.updateAccountCurrentBalance(account, name: account.name, kind: account.kind, currentBalanceInCents: 200_000, in: context)
        #expect(try FinancialSummary.balance(of: account) == 200_000)
        let before = try FinancialSummary.monthlySummary(transactions: context.fetch(FetchDescriptor<FinancialTransaction>()), monthContaining: Date())
        try FinancialOperations.transfer(amountInCents: 30_000, date: Date(), from: account, to: box, in: context)
        #expect(try FinancialSummary.availableMoney(accounts: [account, box]) == 170_000)
        #expect(try FinancialSummary.netWorth(accounts: [account, box]) == 300_000)
        try FinancialOperations.updateAccountCurrentBalance(account, name: account.name, kind: account.kind, currentBalanceInCents: 150_000, in: context)
        #expect(try FinancialSummary.balance(of: account) == 150_000)
        #expect(try FinancialSummary.balance(of: box) == 130_000)
        try FinancialOperations.updateAccountCurrentBalance(account, name: account.name, kind: account.kind, currentBalanceInCents: 150_000, in: context)
        #expect(try FinancialSummary.availableMoney(accounts: [account, box]) == 150_000)
        #expect(try FinancialSummary.monthlySummary(transactions: context.fetch(FetchDescriptor<FinancialTransaction>()), monthContaining: Date()) == before)
        #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 1)
    }

    @Test
    func availableMoneyExcludesInactiveAccountsAndAllBoxes() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let legacy = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        legacy.kind = .other
        let box = FinancialAccount(name: "Saldo desconhecido", kind: .savingsBox)
        let cash = FinancialAccount(name: "Dinheiro", kind: .cash, openingBalanceInCents: 500)
        let inactive = FinancialAccount(name: "Inativa", kind: .checking, openingBalanceInCents: 9999)
        inactive.isActive = false
        for account in [box, cash, inactive] { context.insert(account) }
        try context.save()
        #expect(try FinancialSummary.availableMoney(accounts: [legacy, box, cash, inactive]) == nil)
        try FinancialOperations.updateAccountCurrentBalance(legacy, name: legacy.name, kind: .other, currentBalanceInCents: -100, in: context)
        #expect(try FinancialSummary.availableMoney(accounts: [legacy, box, cash, inactive]) == 400)
        #expect(try FinancialSummary.availableMoney(accounts: [box]) == 0)
        #expect(try FinancialSummary.netWorth(accounts: [legacy, box, cash, inactive]) == nil)
    }
}
