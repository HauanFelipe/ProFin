import Foundation
import SwiftData

typealias MonthlyPlanSettings = ProFinSchemaV9.MonthlyPlanSettings
typealias MonthlyAllocationRule = ProFinSchemaV9.MonthlyAllocationRule

extension ProFinSchemaV9 {
    @Model final class MonthlyPlanSettings {
        @Attribute(.unique) var key: String
        var month: Date
        var extraExpensesInCents: Int64
        var marginInCents: Int64
        init(month: Date, key: String, extras: Int64, margin: Int64) {
            self.month = month; self.key = key; extraExpensesInCents = extras; marginInCents = margin
        }
    }
    @Model final class MonthlyAllocationRule {
        var id: UUID
        // ID é estável e evita apagar o planejamento ao arquivar uma conta.
        @Attribute(.unique) var accountID: UUID
        var monthlyAmountInCents: Int64
        var priority: Int
        init(accountID: UUID, amount: Int64, priority: Int) {
            id = UUID(); self.accountID = accountID; monthlyAmountInCents = amount; self.priority = priority
        }
    }
}
