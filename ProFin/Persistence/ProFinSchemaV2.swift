import Foundation
import SwiftData

// Retrato da V2. Preservar para migrar bancos que já contêm contas e transferências.
enum ProFinSchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [FinancialTransaction.self, Category.self, FinancialAccount.self, AccountTransfer.self]
    }
}

extension ProFinSchemaV2 {
    @Model
    final class FinancialTransaction {
        @Attribute(.unique) var id: UUID
        var title: String
        var amountInCents: Int64
        var date: Date
        var category: Category
        var type: TransactionType
        var classification: ExpenseClassification?
        var notes: String?
        // Opcional apenas para permitir a migração dos lançamentos da V1.
        var account: FinancialAccount?

        init(
            title: String,
            amountInCents: Int64,
            date: Date,
            category: Category,
            type: TransactionType,
            account: FinancialAccount,
            classification: ExpenseClassification? = nil,
            notes: String? = nil
        ) {
            self.id = UUID()
            self.title = title
            self.amountInCents = amountInCents
            self.date = date
            self.category = category
            self.type = type
            self.classification = type == .expense ? classification : nil
            self.notes = notes
            self.account = account
        }
    }
}

extension ProFinSchemaV2 {
    @Model
    final class Category {
        // Mantém os UUIDs existentes sem o índice incompatível com
        // a inversa obrigatória FinancialTransaction.category e .deny.
        var id: UUID
        var name: String
        var isActive: Bool

        @Relationship(deleteRule: .deny, inverse: \FinancialTransaction.category)
        var transactions: [FinancialTransaction] = []

        init(name: String) {
            self.id = UUID()
            self.name = name
            self.isActive = true
        }
    }
}

extension ProFinSchemaV2 {
    @Model
    final class FinancialAccount {
        // UUID gerado pelo app. .unique é incompatível com as inversas
        // obrigatórias de transferências protegidas pela regra .deny.
        var id: UUID
        var name: String
        var kindRawValue: String
        // Saldo anterior a TODOS os lançamentos da conta. nil significa desconhecido.
        var openingBalanceInCents: Int64?
        var isActive: Bool

        @Relationship(deleteRule: .deny, inverse: \FinancialTransaction.account)
        var transactions: [FinancialTransaction] = []

        @Relationship(deleteRule: .deny, inverse: \AccountTransfer.sourceAccount)
        var outgoingTransfers: [AccountTransfer] = []

        @Relationship(deleteRule: .deny, inverse: \AccountTransfer.destinationAccount)
        var incomingTransfers: [AccountTransfer] = []

        var kind: FinancialAccountKind {
            get { FinancialAccountKind(rawValue: kindRawValue) ?? .other }
            set { kindRawValue = newValue.rawValue }
        }

        init(
            id: UUID = UUID(),
            name: String,
            kind: FinancialAccountKind = .other,
            openingBalanceInCents: Int64? = nil
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kind.rawValue
            self.openingBalanceInCents = openingBalanceInCents
            self.isActive = true
        }
    }
}

extension ProFinSchemaV2 {
    @Model
    final class AccountTransfer {
        @Attribute(.unique) var id: UUID
        var amountInCents: Int64
        var date: Date
        var sourceAccount: FinancialAccount
        var destinationAccount: FinancialAccount
        var notes: String?

        init(
            amountInCents: Int64,
            date: Date,
            sourceAccount: FinancialAccount,
            destinationAccount: FinancialAccount,
            notes: String? = nil
        ) {
            self.id = UUID()
            self.amountInCents = amountInCents
            self.date = date
            self.sourceAccount = sourceAccount
            self.destinationAccount = destinationAccount
            self.notes = notes
        }
    }
}
