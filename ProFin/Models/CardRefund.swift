import Foundation
import SwiftData

typealias CardRefund = ProFinSchemaV9.CardRefund

extension ProFinSchemaV9 {
    @Model final class CardRefund {
        var id: UUID
        var purchase: CardPurchase
        var invoice: CardInvoice
        var amountInCents: Int64
        var date: Date
        var notes: String?

        init(purchase: CardPurchase, invoice: CardInvoice, amount: Int64, date: Date, notes: String?) {
            id = UUID(); self.purchase = purchase; self.invoice = invoice
            amountInCents = amount; self.date = date; self.notes = notes
        }
    }
}
