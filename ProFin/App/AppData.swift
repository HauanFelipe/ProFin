import Foundation
import SwiftData

enum AppData {
    static let contextDiscarded = Notification.Name("ProFin.contextDiscarded")

    static func makeContext(for container: ModelContainer) -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    // Não reutilizar Models de um contexto cujo save falhou. O rollback do
    // SwiftData pode deixar inversas em cache ou invalidar relações obrigatórias.
    // A interface substitui o contexto inteiro, preservando o estado do formulário.
    static func discardFailedContext(_ context: ModelContext) {
        context.rollback()
        NotificationCenter.default.post(name: contextDiscarded, object: context)
    }

    // Identidade estável: renomear a conta inicial não pode duplicá-la na retomada.
    static let initialAccountID = UUID(uuidString: "2389AC68-4C4D-49FB-8F14-C57A373A8926")!

    static func makeContainer(at url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: ProFinSchemaV9.self)
        // O banco do ProFin fica separado do banco de exemplo criado pelo Xcode.
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration("ProFin", schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                "ProFin", schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none
            )
        }
        let container = try ModelContainer(
            for: schema, migrationPlan: ProFinMigrationPlan.self, configurations: [configuration]
        )
        container.mainContext.autosaveEnabled = false
        // Executado antes de disponibilizar o contexto às telas. Pode ser retomado
        // caso o app tenha sido interrompido após migrar a estrutura do banco.
        try assignInitialAccount(in: container.mainContext)
        try normalizeAccountKinds(in: container.mainContext)
        try seedCategories(in: container.mainContext)
        try RecurringExpenseOperations.generateDueOccurrences(in: container.mainContext)
        return container
    }

    static func assignInitialAccount(in context: ModelContext) throws {
        let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
        let unassigned = try context.fetch(FetchDescriptor<FinancialTransaction>(
            predicate: #Predicate { $0.account == nil }
        ))
        guard accounts.isEmpty || !unassigned.isEmpty else { return }

        let account: FinancialAccount
        if let existing = accounts.first(where: { $0.id == initialAccountID }) {
            account = existing
        } else {
            account = FinancialAccount(id: initialAccountID, name: "Conta Principal", kind: .checking,
                                       createdAt: unassigned.isEmpty ? Date() : nil)
            context.insert(account)
        }
        for transaction in unassigned {
            transaction.account = account
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    static func seedCategories(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<Category>()) == 0 else { return }

        let names = [
            "Alimentação", "Transporte", "Educação", "Lazer", "Assinaturas",
            "Saúde", "Casa", "Compras", "Outros", "Salário"
        ]

        for name in names {
            context.insert(Category(name: name))
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    // Retomável: converte somente o tipo antigo, sem alterar nomes, IDs ou valores.
    static func normalizeAccountKinds(in context: ModelContext) throws {
        let accounts = try context.fetch(FetchDescriptor<FinancialAccount>())
        for account in accounts where account.kindRawValue == "turboBox" {
            account.kind = .savingsBox
        }
        if context.hasChanges { try FinancialOperations.save(in: context) }
    }
}
