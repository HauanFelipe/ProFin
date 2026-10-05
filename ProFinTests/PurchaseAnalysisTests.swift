import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct PurchaseAnalysisTests {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private var calendar: Calendar { SavingsYieldCalculator.calendar }

    private func setup() throws -> (ModelContainer, FinancialAccount, FinancialAccount, Goal) {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let cash = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        cash.openingBalanceInCents = 200_000
        let box = try FinancialOperations.createAccount(name: "Monitor", kind: .savingsBox, openingBalanceInCents: 60_000, in: context)
        let goal = try GoalOperations.create(name: "Monitor", targetAmountInCents: 150_000, account: box, in: context)
        return (container, cash, box, goal)
    }

    private func bill(_ amount: Int64?, date: Date, in context: ModelContext) throws -> RecurringExpenseOccurrence {
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let month = calendar.dateInterval(of: .month, for: date)!.start
        let expense = RecurringExpense(title: "Conta", category: category, expectedAmountInCents: amount,
            dueDay: 10, amountType: amount == nil ? .variable : .fixed, classification: .essential, startMonth: month, createdAt: date)
        expense.isActive = false
        context.insert(expense)
        let occurrence = RecurringExpenseOccurrence(expense: expense, month: month, dueDate: date, key: UUID().uuidString)
        context.insert(occurrence)
        try context.save()
        return occurrence
    }

    private func analyze(_ goal: Goal, context: ModelContext, price: Int64 = 150_000, extras: Int64 = 0,
                         margin: Int64 = 0, costs: Int64 = 0) throws -> PurchaseAnalysis {
        try PurchaseAnalysisService.analyze(goal: goal, accounts: context.fetch(FetchDescriptor<FinancialAccount>()),
            occurrences: context.fetch(FetchDescriptor<RecurringExpenseOccurrence>()),
            transactions: context.fetch(FetchDescriptor<FinancialTransaction>()), purchaseInCents: price,
            extraExpensesInCents: extras, marginInCents: margin, costsInCents: costs, now: now, calendar: calendar)
    }

    @Test
    func explicitFormulaIncludesArrearsAndExcludesOtherBoxes() throws {
        let (container, _, _, goal) = try setup()
        let context = container.mainContext
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: now)!
        _ = try bill(36_000, date: previousMonth, in: context)
        _ = try bill(50_000, date: now, in: context)
        _ = try bill(999_999, date: calendar.date(byAdding: .month, value: 1, to: now)!, in: context)
        _ = try FinancialOperations.createAccount(name: "Emergência", kind: .savingsBox, openingBalanceInCents: 900_000,
                                                   isEmergencyReserve: true, in: context)
        let otherBox = try FinancialOperations.createAccount(name: "Outra meta", kind: .savingsBox, openingBalanceInCents: 500_000, in: context)
        _ = try GoalOperations.create(name: "Viagem", targetAmountInCents: 600_000, account: otherBox, in: context)
        let result = try analyze(goal, context: context, extras: 14_000, margin: 30_000)
        #expect(result.cashInCents == 200_000)
        #expect(result.goalBoxInCents == 60_000)
        #expect(result.pendingInCents == 86_000)
        #expect(result.pendingBills.count == 2)
        #expect(result.remainingInCents == -20_000)
        #expect(result.explanation.contains("Faltam"))
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(!context.hasChanges)
    }

    @Test
    func paymentReducesCashInsteadOfBeingDeductedTwice() throws {
        let (container, cash, _, goal) = try setup()
        let context = container.mainContext
        let occurrence = try bill(65_000, date: now, in: context)
        let before = try analyze(goal, context: context)
        let payment = try FinancialOperations.recordTransaction(title: "Pagamento", amountInCents: 65_000,
            date: now, category: occurrence.category, type: .expense, account: cash, classification: .essential, in: context)
        occurrence.paymentTransaction = payment
        try context.save()
        let after = try analyze(goal, context: context)
        #expect(before.remainingInCents == after.remainingInCents)
        #expect(after.pendingInCents == 0)
        #expect(after.cashInCents == 135_000)
        #expect(after.monthly.expenseInCents == 65_000)
    }

    @Test
    func missingValuesBlockConclusionButNotExcludedUnknownBoxes() throws {
        let (container, cash, _, goal) = try setup()
        let context = container.mainContext
        context.insert(FinancialAccount(name: "Outra caixinha desconhecida", kind: .savingsBox))
        try context.save()
        #expect(try analyze(goal, context: context).remainingInCents == 110_000)
        _ = try bill(nil, date: now, in: context)
        #expect(try analyze(goal, context: context).remainingInCents == nil)
        cash.openingBalanceInCents = nil
        try context.save()
        let result = try analyze(goal, context: context)
        #expect(result.missingInformation.count == 2)
        #expect(result.remainingInCents == nil)
    }

    @Test
    func noLinkedBoxAndZeroSurplusAndFees() throws {
        let (container, _, _, goal) = try setup()
        let context = container.mainContext
        try GoalOperations.update(goal, name: goal.name, targetAmountInCents: 150_000, account: nil, in: context)
        let result = try analyze(goal, context: context, extras: 20_000, margin: 20_000, costs: 10_000)
        #expect(result.goalBoxInCents == 0)
        #expect(result.remainingInCents == 0)
        #expect(result.explanation.contains("não sobra"))
        #expect(try analyze(goal, context: context).remainingInCents == 50_000)
        #expect(throws: (any Error).self) { try analyze(goal, context: context, extras: -1) }
        try GoalOperations.setArchived(goal, archived: true, in: context)
        #expect(throws: (any Error).self) { try analyze(goal, context: context) }
    }

    @Test
    func reserveProtectionRequiresReleasingGoalAndPreventsReactivation() throws {
        let (container, _, box, goal) = try setup()
        let context = container.mainContext
        #expect(throws: GoalOperationError.accountHasActiveGoal) {
            try FinancialOperations.updateAccount(box, name: box.name, kind: .savingsBox, openingBalanceInCents: 60_000,
                                                 isEmergencyReserve: true, in: context)
        }
        #expect(!box.isEmergencyReserve)
        #expect(!context.hasChanges)
        try GoalOperations.setArchived(goal, archived: true, in: context)
        try FinancialOperations.updateAccount(box, name: box.name, kind: .savingsBox, openingBalanceInCents: 60_000,
                                             isEmergencyReserve: true, in: context)
        #expect(throws: GoalOperationError.protectedReserve) { try GoalOperations.setArchived(goal, archived: false, in: context) }
        #expect(throws: GoalOperationError.protectedReserve) {
            try GoalOperations.create(name: "Compra", targetAmountInCents: 100, account: box, in: context)
        }
        #expect(try FinancialSummary.balance(of: box) == 60_000)
    }

    @Test
    func transferIntoGoalBoxKeepsAnalysisTotalUnchanged() throws {
        let (container, cash, box, goal) = try setup()
        let context = container.mainContext
        let before = try analyze(goal, context: context)
        try FinancialOperations.transfer(amountInCents: 30_000, date: now, from: cash, to: box, in: context)
        let after = try analyze(goal, context: context)
        #expect(before.remainingInCents == after.remainingInCents)
        #expect(after.cashInCents == 170_000)
        #expect(after.goalBoxInCents == 90_000)
    }

    @Test
    func v6MigrationPreservesGoalAndProtectionPersists() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "ProFin.store")
        let accountID = UUID()
        var goalID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: ProFinSchemaV6.self)
            let config = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let box = ProFinSchemaV6.FinancialAccount(id: accountID, name: "Reserva", kind: .savingsBox, openingBalanceInCents: 60_000)
            let goal = ProFinSchemaV6.Goal(name: "Monitor", targetAmountInCents: 150_000, savingsAccount: box)
            goalID = goal.id
            container.mainContext.insert(box)
            container.mainContext.insert(goal)
            try container.mainContext.save()
        }
        try autoreleasepool {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let goal = try #require(context.fetch(FetchDescriptor<Goal>()).first)
            let box = try #require(goal.savingsAccount)
            #expect(goal.id == goalID)
            #expect(box.id == accountID)
            #expect(!box.isEmergencyReserve)
            #expect(try FinancialSummary.balance(of: box) == 60_000)
            try GoalOperations.setArchived(goal, archived: true, in: context)
            try FinancialOperations.updateAccount(box, name: box.name, kind: box.kind,
                openingBalanceInCents: box.openingBalanceInCents, isEmergencyReserve: true, in: context)
        }
        try autoreleasepool {
            let container = try AppData.makeContainer(at: url)
            let goal = try #require(container.mainContext.fetch(FetchDescriptor<Goal>()).first)
            #expect(goal.isArchived)
            #expect(goal.savingsAccount?.isEmergencyReserve == true)
            #expect(goal.savingsAccount?.id == accountID)
        }
    }
}
