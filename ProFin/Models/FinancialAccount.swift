import Foundation
import SwiftData

enum FinancialAccountKind: String, CaseIterable, Identifiable {
    case checking
    case savingsBox
    case turboBox
    case other

    var id: String { rawValue }
}

typealias FinancialAccount = ProFinSchemaV3.FinancialAccount

extension ProFinSchemaV3 {
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
