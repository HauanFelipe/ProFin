import Foundation
import SwiftData

enum FinancialAccountKind: String, CaseIterable, Identifiable {
    case checking
    case savingsBox
    case cash
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checking: "Conta corrente"
        case .savingsBox: "Caixinha"
        case .cash: "Dinheiro"
        case .other: "Outro"
        }
    }
}

typealias FinancialAccount = ProFinSchemaV9.FinancialAccount

extension ProFinSchemaV9 {
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
        var isEmergencyReserve: Bool = false
        // nil para contas antigas, cuja data de criação não era registrada.
        var createdAt: Date?

        @Relationship(deleteRule: .deny, inverse: \FinancialTransaction.account)
        var transactions: [FinancialTransaction] = []

        @Relationship(deleteRule: .deny, inverse: \AccountTransfer.sourceAccount)
        var outgoingTransfers: [AccountTransfer] = []

        @Relationship(deleteRule: .deny, inverse: \AccountTransfer.destinationAccount)
        var incomingTransfers: [AccountTransfer] = []

        @Relationship(deleteRule: .deny, inverse: \CardInvoicePayment.account)
        var cardPayments: [CardInvoicePayment] = []

        var kind: FinancialAccountKind {
            get { FinancialAccountKind(rawValue: kindRawValue) ?? .other }
            set { kindRawValue = newValue.rawValue }
        }

        init(
            id: UUID = UUID(),
            name: String,
            kind: FinancialAccountKind = .other,
            openingBalanceInCents: Int64? = nil,
            createdAt: Date? = Date()
        ) {
            self.id = id
            self.name = name
            self.kindRawValue = kind.rawValue
            self.openingBalanceInCents = openingBalanceInCents
            self.isActive = true
            self.createdAt = createdAt
        }
    }
}
