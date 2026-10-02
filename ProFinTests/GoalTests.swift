import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct GoalTests {
    private func box(in context: ModelContext, balance: Int64? = 120_000) throws -> FinancialAccount {
        let box = FinancialAccount(name: "Reserva", kind: .savingsBox, openingBalanceInCents: balance)
        context.insert(box)
        try context.save()
        return box
    }

    @Test
    func progressTracksTransfersWithoutChangingMonthlyResult() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let box = try box(in: context)
        let destination = try FinancialOperations.createAccount(name: "Corrente", kind: .checking, openingBalanceInCents: 0, in: context)
        let goal = try GoalOperations.create(name: " Monitor ", targetAmountInCents: 180_000, account: box, in: context)
        #expect(goal.name == "Monitor")
        #expect(try GoalSummary.progress(for: goal) == .available(balance: 120_000, remaining: 60_000, fraction: 2.0 / 3))
        try FinancialOperations.transfer(amountInCents: 30_000, date: Date(), from: box, to: destination, in: context)
        #expect(try GoalSummary.progress(for: goal) == .available(balance: 90_000, remaining: 90_000, fraction: 0.5))
        try FinancialOperations.transfer(amountInCents: 30_000, date: Date(), from: destination, to: box, in: context)
        #expect(try GoalSummary.progress(for: goal) == .available(balance: 120_000, remaining: 60_000, fraction: 2.0 / 3))
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(try FinancialSummary.netWorth(accounts: [box, destination]) == 120_000)
    }

    @Test
    func boundsUnknownAndUnlinkedStates() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let box = try box(in: context, balance: nil)
        let goal = try GoalOperations.create(name: "Meta", targetAmountInCents: 100, account: nil, in: context)
        #expect(try GoalSummary.progress(for: goal) == .unlinked)
        try GoalOperations.update(goal, name: goal.name, targetAmountInCents: 100, account: box, in: context)
        #expect(try GoalSummary.progress(for: goal) == .unknownBalance)
        for balance: Int64 in [-100, 0, 100, 200, Int64.max] {
            box.openingBalanceInCents = balance
            let covered = min(100, max(0, balance))
            #expect(try GoalSummary.progress(for: goal) == .available(balance: balance, remaining: 100 - covered, fraction: Double(covered) / 100))
        }
        box.isActive = false
        #expect(try GoalSummary.progress(for: goal) == .unavailableAccount)
    }

    @Test
    func exclusiveLinkArchiveAndReactivation() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let box = try box(in: context)
        let first = try GoalOperations.create(name: "Monitor", targetAmountInCents: 180_000, account: box, in: context)
        #expect(throws: GoalOperationError.accountAlreadyLinked) {
            try GoalOperations.create(name: "Teclado", targetAmountInCents: 20_000, account: box, in: context)
        }
        #expect(!context.hasChanges)
        try GoalOperations.update(first, name: "Monitor novo", targetAmountInCents: 200_000, account: box, in: context)
        try GoalOperations.setArchived(first, archived: true, in: context)
        #expect(try GoalSummary.progress(for: first) == .archived)
        #expect(first.savingsAccount?.id == box.id)
        let second = try GoalOperations.create(name: "Teclado", targetAmountInCents: 20_000, account: box, in: context)
        #expect(throws: GoalOperationError.accountAlreadyLinked) {
            try GoalOperations.setArchived(first, archived: false, in: context)
        }
        #expect(first.isArchived)
        try GoalOperations.update(second, name: second.name, targetAmountInCents: second.targetAmountInCents, account: nil, in: context)
        try GoalOperations.setArchived(first, archived: false, in: context)
        #expect(!first.isArchived)
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 2)
    }

    @Test
    func invalidInputAndAccountChangesDoNotMutateData() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let box = try box(in: context, balance: 0)
        #expect(throws: GoalOperationError.invalidName) {
            try GoalOperations.create(name: "  ", targetAmountInCents: 100, account: box, in: context)
        }
        for target: Int64 in [0, -100] {
            #expect(throws: GoalOperationError.invalidTarget) {
                try GoalOperations.create(name: "Meta", targetAmountInCents: target, account: box, in: context)
            }
        }
        let checking = try FinancialOperations.createAccount(name: "Corrente", kind: .checking, openingBalanceInCents: 0, in: context)
        #expect(throws: GoalOperationError.invalidAccount) {
            try GoalOperations.create(name: "Meta", targetAmountInCents: 100, account: checking, in: context)
        }
        let goal = try GoalOperations.create(name: "Meta", targetAmountInCents: 100, account: box, in: context)
        #expect(throws: GoalOperationError.accountHasActiveGoal) {
            try FinancialOperations.setAccountActive(box, active: false, in: context)
        }
        #expect(throws: GoalOperationError.accountHasActiveGoal) {
            try FinancialOperations.updateAccount(box, name: "Dinheiro", kind: .cash, openingBalanceInCents: 0, in: context)
        }
        #expect(throws: GoalOperationError.accountHasActiveGoal) { try FinancialOperations.deleteAccount(box, in: context) }
        #expect(box.kind == .savingsBox)
        #expect(box.name == "Reserva")
        #expect(box.isActive)
        #expect(!context.hasChanges)
        try GoalOperations.setArchived(goal, archived: true, in: context)
        try FinancialOperations.setAccountActive(box, active: false, in: context)
        #expect(throws: GoalOperationError.invalidAccount) { try GoalOperations.setArchived(goal, archived: false, in: context) }
        try FinancialOperations.deleteAccount(box, in: context)
        #expect(goal.savingsAccount == nil)
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 1)
    }

    @Test
    func deletingGoalPreservesAccountAndItsHistory() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let box = try box(in: context)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let income = try FinancialOperations.recordTransaction(title: "Rendimento registrado", amountInCents: 500,
            date: Date(), category: category, type: .income, account: box, in: context)
        let goal = try GoalOperations.create(name: "Monitor", targetAmountInCents: 180_000, account: box, in: context)
        try GoalOperations.delete(goal, in: context)
        #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 0)
        #expect(try FinancialSummary.balance(of: box) == 120_500)
        #expect(box.transactions.first?.id == income.id)
        _ = try GoalOperations.create(name: "Outra meta", targetAmountInCents: 100, account: box, in: context)
    }

    @Test
    func migrationAndReopeningPreserveAllExistingData() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "ProFin.store")
        let boxID = UUID()
        var goalID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: ProFinSchemaV5.self)
            let config = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            let box = ProFinSchemaV5.FinancialAccount(id: boxID, name: "Turbo", kind: .savingsBox, openingBalanceInCents: 120_000)
            context.insert(box)
            let projection = ProFinSchemaV5.SavingsYieldConfiguration(accountID: boxID, annualCDIBasisPoints: 1000,
                cdiPercentageBasisPoints: 12_000, referenceDate: Date(), businessDays: 10, ledgerSignature: "old")
            projection.lots = [ProFinSchemaV5.SavingsYieldLot(input: SavingsYieldLotInput(applicationDate: Date(), principalInCents: 120_000, grossBalanceInCents: 120_000))]
            context.insert(projection)
            try context.save()
        }
        try autoreleasepool {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 0)
            let box = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first { $0.id == boxID })
            #expect(try FinancialSummary.balance(of: box) == 120_000)
            let projection = try #require(context.fetch(FetchDescriptor<SavingsYieldConfiguration>()).first)
            #expect(projection.cdiPercentageBasisPoints == 12_000)
            #expect(projection.lots.count == 1)
            let goal = try GoalOperations.create(name: "Monitor", targetAmountInCents: 180_000, account: box, in: context)
            goalID = goal.id
        }
        try autoreleasepool {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let goal = try #require(context.fetch(FetchDescriptor<Goal>()).first)
            #expect(goal.id == goalID)
            #expect(goal.savingsAccount?.id == boxID)
            #expect(try GoalSummary.progress(for: goal) == .available(balance: 120_000, remaining: 60_000, fraction: 2.0 / 3))
            #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
            try GoalOperations.delete(goal, in: context)
        }
        try autoreleasepool {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            #expect(try context.fetchCount(FetchDescriptor<Goal>()) == 0)
            let box = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first { $0.id == boxID })
            #expect(try FinancialSummary.balance(of: box) == 120_000)
            #expect(try context.fetchCount(FetchDescriptor<SavingsYieldConfiguration>()) == 1)
        }
    }
}
