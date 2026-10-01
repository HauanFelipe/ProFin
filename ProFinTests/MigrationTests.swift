import Foundation
import SwiftData
import Testing
@testable import ProFin

@MainActor
struct MigrationTests {
    private func temporaryStore() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "ProFin.store")
    }

    @Test(arguments: [false, true])
    func migratesLegacyStoreAndReopensWithoutDuplicatingData(versioned: Bool) throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        var transactionID = UUID()
        var categoryID = UUID()
        var incomeID = UUID()

        do {
            // Sem versionamento reproduz a configuração usada antes desta evolução.
            let schema = versioned
                ? Schema(versionedSchema: ProFinSchemaV1.self)
                : Schema([ProFinSchemaV1.FinancialTransaction.self, ProFinSchemaV1.Category.self])
            let configuration = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            context.autosaveEnabled = false
            let category = ProFinSchemaV1.Category(name: "Categoria personalizada")
            category.isActive = false
            categoryID = category.id
            context.insert(category)
            let transaction = ProFinSchemaV1.FinancialTransaction(
                title: "Pagamento antigo", amountInCents: 12_345, date: date, category: category,
                type: .expense, classification: .nonEssential, notes: "Observação original"
            )
            let income = ProFinSchemaV1.FinancialTransaction(
                title: "Receita antiga", amountInCents: 50_000, date: date,
                category: category, type: .income
            )
            transactionID = transaction.id
            incomeID = income.id
            context.insert(transaction)
            context.insert(income)
            try context.save()
        }

        do {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let transactions = try context.fetch(FetchDescriptor<FinancialTransaction>())
            let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
            let categories = try context.fetch(FetchDescriptor<ProFin.Category>())
            #expect(transactions.count == 2)
            #expect(accounts.count == 1)
            #expect(categories.count == 1)
            let account = try #require(accounts.first)
            #expect(account.id == AppData.initialAccountID)
            #expect(account.name == "Conta inicial")
            #expect(account.kind == .other)
            #expect(account.openingBalanceInCents == nil)
            #expect(account.transactions.count == 2)
            #expect(try FinancialSummary.netWorth(accounts: accounts) == nil)
            let transaction = try #require(transactions.first { $0.id == transactionID })
            #expect(transaction.title == "Pagamento antigo")
            #expect(transaction.amountInCents == 12_345)
            #expect(transaction.date == date)
            #expect(transaction.type == .expense)
            #expect(transaction.classification == .nonEssential)
            #expect(transaction.notes == "Observação original")
            #expect(transaction.category.id == categoryID)
            #expect(transaction.category.name == "Categoria personalizada")
            #expect(!transaction.category.isActive)
            #expect(transaction.account?.id == account.id)
            let income = try #require(transactions.first { $0.id == incomeID })
            #expect(income.type == .income)
            #expect(income.amountInCents == 50_000)
            #expect(income.classification == nil)
            #expect(income.account?.id == account.id)
            #expect(try FinancialSummary.monthlySummary(transactions: transactions, monthContaining: date)
                == MonthlySummary(incomeInCents: 50_000, expenseInCents: 12_345, resultInCents: 37_655))
            account.name = "Minha conta renomeada"
            try context.save()
        }

        // Duas reaberturas verificam a retomada idempotente do preenchimento.
        for _ in 0..<2 {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            #expect(try context.fetchCount(FetchDescriptor<FinancialAccount>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 2)
            #expect(try context.fetchCount(FetchDescriptor<ProFin.Category>()) == 1)
            #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
            let account = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
            #expect(account.name == "Minha conta renomeada")
            #expect(Set(account.transactions.map(\.id)) == [transactionID, incomeID])
        }
    }

    @Test
    func resumesAccountAssignmentAfterSchemaMigration() throws {
        let container = try AppData.makeContainer(inMemory: true)
        let context = container.mainContext
        let initial = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let category = try #require(context.fetch(FetchDescriptor<ProFin.Category>()).first)
        let other = FinancialAccount(name: "Outra conta", kind: .checking, openingBalanceInCents: 0)
        context.insert(other)
        let orphan = FinancialTransaction(
            title: "Legado", amountInCents: 100, date: Date(), category: category, type: .income, account: initial
        )
        context.insert(orphan)
        orphan.account = nil
        let assigned = FinancialTransaction(
            title: "Já associado", amountInCents: 200, date: Date(), category: category, type: .income, account: other
        )
        context.insert(assigned)
        initial.name = "Renomeada"
        try context.save()

        try AppData.assignInitialAccount(in: context)
        try AppData.assignInitialAccount(in: context)
        #expect(orphan.account?.id == initial.id)
        #expect(assigned.account?.id == other.id)
        #expect(try context.fetchCount(FetchDescriptor<FinancialAccount>()) == 2)
        #expect(initial.name == "Renomeada")
    }

    @Test
    func failedTransferSaveRecoversWithFreshContext() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        do {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let source = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
            source.openingBalanceInCents = 200_000
            context.insert(FinancialAccount(name: "Destino", openingBalanceInCents: 100_000))
            try context.save()
        }

        do {
            // Um store somente leitura provoca falha real de gravação sem
            // invalidar previamente os vínculos de outros registros.
            let schema = Schema(versionedSchema: ProFinSchemaV3.self)
            let configuration = ModelConfiguration(
                "ProFin", schema: schema, url: url, allowsSave: false, cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            var context = AppData.makeContext(for: container)
            for _ in 0..<2 {
                let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
                let source = try #require(accounts.first { $0.id == AppData.initialAccountID })
                let destination = try #require(accounts.first { $0.id != AppData.initialAccountID })
                #expect(throws: (any Error).self) {
                    try FinancialOperations.transfer(
                        amountInCents: 30_000, date: Date(), from: source, to: destination, in: context
                    )
                }
                // Mesmo procedimento usado pela interface após contextDiscarded.
                context = AppData.makeContext(for: container)
                let recoveredAccounts = try context.fetch(FetchDescriptor<FinancialAccount>())
                let recoveredSource = try #require(recoveredAccounts.first { $0.id == AppData.initialAccountID })
                let recoveredDestination = try #require(recoveredAccounts.first { $0.id != AppData.initialAccountID })
                #expect(!context.hasChanges)
                #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
                #expect(recoveredSource.outgoingTransfers.isEmpty)
                #expect(recoveredDestination.incomingTransfers.isEmpty)
                #expect(try FinancialSummary.balance(of: recoveredSource) == 200_000)
                #expect(try FinancialSummary.balance(of: recoveredDestination) == 100_000)
            }
        }

        let reopened = try AppData.makeContainer(at: url)
        let context = reopened.mainContext
        let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
        let source = try #require(accounts.first { $0.id == AppData.initialAccountID })
        let destination = try #require(accounts.first { $0.id != AppData.initialAccountID })
        #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
        try FinancialOperations.transfer(
            amountInCents: 30_000, date: Date(), from: source, to: destination, in: context
        )
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 1)
        #expect(source.outgoingTransfers.count == 1)
        #expect(destination.incomingTransfers.count == 1)
        #expect(try FinancialSummary.balance(of: source) == 170_000)
        #expect(try FinancialSummary.balance(of: destination) == 130_000)
    }

    @Test
    func storeRejectsDeletingAccountsReferencedByTransfers() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let container = try AppData.makeContainer(at: url)
        let context = container.mainContext
        let source = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
        let destination = FinancialAccount(name: "Destino", openingBalanceInCents: 0)
        context.insert(destination)
        try context.save()
        let transfer = try FinancialOperations.transfer(
            amountInCents: 100, date: Date(), from: source, to: destination, in: context
        )
        let transferID = transfer.id
        for account in [source, destination] {
            context.delete(account)
            #expect(throws: (any Error).self) { try context.save() }
            context.rollback()
        }
        #expect(try context.fetchCount(FetchDescriptor<FinancialAccount>()) == 2)
        #expect(try context.fetch(FetchDescriptor<AccountTransfer>()).first?.id == transferID)
    }

    @Test
    func transferSurvivesReopeningAndDeletionRestoresBalances() throws {
        let url = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var transferID = UUID()
        do {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let checking = try #require(context.fetch(FetchDescriptor<FinancialAccount>()).first)
            checking.kind = .checking
            checking.openingBalanceInCents = 200_000
            let turbo = FinancialAccount(name: "Turbo", kind: .turboBox, openingBalanceInCents: 100_000)
            context.insert(turbo)
            try context.save()
            let transfer = try FinancialOperations.transfer(
                amountInCents: 30_000, date: Date(), from: checking, to: turbo,
                notes: "Reserva", in: context
            )
            transferID = transfer.id
        }
        do {
            let container = try AppData.makeContainer(at: url)
            let context = container.mainContext
            let transfer = try #require(context.fetch(FetchDescriptor<AccountTransfer>()).first)
            #expect(transfer.id == transferID)
            #expect(transfer.notes == "Reserva")
            #expect(transfer.sourceAccount.kind == .checking)
            #expect(transfer.destinationAccount.kind == .turboBox)
            #expect(transfer.sourceAccount.outgoingTransfers.count == 1)
            #expect(transfer.destinationAccount.incomingTransfers.count == 1)
            #expect(try FinancialSummary.balance(of: transfer.sourceAccount) == 170_000)
            #expect(try FinancialSummary.balance(of: transfer.destinationAccount) == 130_000)
            #expect(try FinancialSummary.netWorth(accounts: context.fetch(FetchDescriptor<FinancialAccount>())) == 300_000)
            #expect(try context.fetchCount(FetchDescriptor<FinancialTransaction>()) == 0)
            context.delete(transfer)
            try context.save()
        }
        let reopened = try AppData.makeContainer(at: url)
        let context = reopened.mainContext
        #expect(try context.fetchCount(FetchDescriptor<AccountTransfer>()) == 0)
        let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
        #expect(accounts.count == 2)
        for account in accounts {
            #expect(try FinancialSummary.balance(of: account) == account.openingBalanceInCents)
            #expect(account.incomingTransfers.isEmpty)
            #expect(account.outgoingTransfers.isEmpty)
        }
    }
}
