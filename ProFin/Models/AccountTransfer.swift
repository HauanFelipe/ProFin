import Foundation
import SwiftData

typealias AccountTransfer = ProFinSchemaV9.AccountTransfer

extension ProFinSchemaV9 {
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
