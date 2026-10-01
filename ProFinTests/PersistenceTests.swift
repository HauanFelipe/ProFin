import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct PersistenceTests {
    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema(versionedSchema: ProFinSchemaV3.self)
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(for: schema, migrationPlan: ProFinMigrationPlan.self, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        return container
    }

    @Test
    func seedsCategoriesOnlyOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        try AppData.seedCategories(in: context)
        let initialIDs = Set(try context.fetch(FetchDescriptor<ProFin.Category>()).map(\.id))
        try AppData.seedCategories(in: context)
        let categories = try context.fetch(FetchDescriptor<ProFin.Category>())

        #expect(categories.count == 10)
        #expect(Set(categories.map(\.id)) == initialIDs)
        #expect(categories.contains { $0.name == "Salário" })
    }

    @Test
    func savesAndDeletesTransactionsWithoutDeletingCategory() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let category = ProFin.Category(name: "Alimentação")
        context.insert(category)
        let transaction = FinancialTransaction(
            title: "Restaurante", amountInCents: 2590, date: Date(), category: category,
            type: .expense, account: FinancialAccount(name: "Conta teste"), classification: .nonEssential, notes: "Almoço"
        )
        context.insert(transaction)
        try context.save()

        let saved = try #require(context.fetch(FetchDescriptor<FinancialTransaction>()).first)
        #expect(saved.amountInCents == 2590)
        #expect(saved.classification == .nonEssential)
        #expect(saved.category.id == category.id)
        #expect(category.transactions.count == 1)

        context.delete(saved)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ProFin.Category>()) == 1)
        #expect(category.transactions.isEmpty)
    }

    @Test
    func keepsIncomeUnclassified() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let category = ProFin.Category(name: "Salário")
        context.insert(category)
        let income = FinancialTransaction(
            title: "Salário", amountInCents: 250000, date: Date(), category: category,
            type: .income, account: FinancialAccount(name: "Conta teste"), classification: .essential
        )
        context.insert(income)
        try context.save()

        let saved = try #require(context.fetch(FetchDescriptor<FinancialTransaction>()).first)
        #expect(saved.type == .income)
        #expect(saved.classification == nil)
    }

    @Test
    func reopensSavedDataAndPersistsDeletion() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "test.store")
        var transactionID: UUID?

        do {
            let container = try makeContainer(at: url)
            let context = container.mainContext
            let category = ProFin.Category(name: "Transporte")
            context.insert(category)
            let transaction = FinancialTransaction(
                title: "Gasolina", amountInCents: 15050, date: Date(), category: category,
                type: .expense, account: FinancialAccount(name: "Conta teste"), classification: .essential, notes: "Teste de persistência"
            )
            transactionID = transaction.id
            context.insert(transaction)
            try context.save()
        }

        do {
            let container = try makeContainer(at: url)
            let context = container.mainContext
            let transactions = try context.fetch(FetchDescriptor<FinancialTransaction>())
            let transaction = try #require(transactions.first)
            #expect(transactions.count == 1)
            #expect(transaction.id == transactionID)
            #expect(transaction.title == "Gasolina")
            #expect(transaction.amountInCents == 15050)
            #expect(transaction.classification == .essential)
            #expect(transaction.category.name == "Transporte")
            #expect(transaction.notes == "Teste de persistência")
            context.delete(transaction)
            try context.save()
        }

        let reopened = try makeContainer(at: url)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
        #expect(try reopened.mainContext.fetchCount(FetchDescriptor<ProFin.Category>()) == 1)
    }
}
