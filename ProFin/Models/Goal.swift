import Foundation
import SwiftData

typealias Goal = ProFinSchemaV6.Goal

extension ProFinSchemaV6 {
@Model
final class Goal {
    var id: UUID
    var name: String
    var targetAmountInCents: Int64
    @Relationship(deleteRule: .nullify) var savingsAccount: FinancialAccount?
    var createdAt: Date
    var isArchived: Bool

    init(name: String, targetAmountInCents: Int64, savingsAccount: FinancialAccount? = nil) {
        id = UUID()
        self.name = name
        self.targetAmountInCents = targetAmountInCents
        self.savingsAccount = savingsAccount
        createdAt = Date()
        isArchived = false
    }
}

}
