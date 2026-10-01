import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct CategoryTests {
    @Test
    func createsActiveCategoryWithoutCreatingFinancialRecords() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let category = try FinancialOperations.createCategory(name: "  Animais   de estimação  ", in: context)
        #expect(category.name == "Animais de estimação")
        #expect(category.isActive)
        #expect(try context.fetchCount(FetchDescriptor<ProFin.Category>()) == 11)
        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RecurringExpense>()) == 0)
        #expect(!context.hasChanges)
    }

    @Test
    func rejectsBlankAndEquivalentNamesWithoutChangingData() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        #expect(throws: FinancialOperationError.emptyCategoryName) {
            try FinancialOperations.createCategory(name: " \n\t ", in: context)
        }
        for name in ["Alimentação", " alimentacao ", "ALIMENTAÇÃO"] {
            #expect(throws: FinancialOperationError.duplicateCategoryName) {
                try FinancialOperations.createCategory(name: name, in: context)
            }
        }
        let custom = try FinancialOperations.createCategory(name: "Cuidados pessoais", in: context)
        custom.isActive = false
        try context.save()
        #expect(throws: FinancialOperationError.duplicateCategoryName) {
            try FinancialOperations.createCategory(name: "cuidados   PESSOAIS", in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<ProFin.Category>()) == 11)
        #expect(!context.hasChanges)
    }

    @Test
    func newCategorySurvivesReopeningAndCanBeUsedInATransaction() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "ProFin.store")
        try autoreleasepool {
            var categoryID = UUID()
            do {
                let container = try AppData.makeContainer(at: url)
                categoryID = try FinancialOperations.createCategory(name: "Pets", in: container.mainContext).id
            }
            let reopened = try AppData.makeContainer(at: url)
            let context = reopened.mainContext
            let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first { $0.id == categoryID })
            let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
            let transaction = try FinancialOperations.recordTransaction(
                title: "Ração", amountInCents: 5000, date: Date(), category: category,
                type: .expense, account: account, classification: .essential, in: context
            )
            #expect(category.name == "Pets")
            #expect(transaction.category.id == categoryID)
            #expect(try context.fetchCount(FetchDescriptor<ProFin.Category>()) == 11)
        }
    }
}
