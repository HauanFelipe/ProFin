import Foundation

struct AccountHistoryEntry: Identifiable {
    let id: String
    let date: Date
    let title: String
    let detail: String
    let amountInCents: Int64
    let isIncoming: Bool
    let notes: String?
    let transactionID: UUID?
    let transferID: UUID?
}

@MainActor
enum AccountHistory {
    static func entries(for account: FinancialAccount, asOf date: Date = Date()) -> [AccountHistoryEntry] {
        var entries = account.transactions.filter { $0.date <= date }.map { transaction in
            AccountHistoryEntry(
                id: "transaction/\(transaction.id)", date: transaction.date, title: transaction.title,
                detail: "\(transaction.type.title) · \(transaction.category.name)",
                amountInCents: transaction.amountInCents, isIncoming: transaction.type == .income,
                notes: transaction.notes, transactionID: transaction.id, transferID: nil
            )
        }
        for transfer in account.incomingTransfers where transfer.date <= date {
            entries.append(AccountHistoryEntry(
                id: "transfer/\(transfer.id)", date: transfer.date, title: "Transferência recebida",
                detail: "De: \(transfer.sourceAccount.name)", amountInCents: transfer.amountInCents,
                isIncoming: true, notes: transfer.notes, transactionID: nil, transferID: transfer.id
            ))
        }
        for transfer in account.outgoingTransfers where transfer.date <= date {
            entries.append(AccountHistoryEntry(
                id: "transfer/\(transfer.id)", date: transfer.date, title: "Transferência enviada",
                detail: "Para: \(transfer.destinationAccount.name)", amountInCents: transfer.amountInCents,
                isIncoming: false, notes: transfer.notes, transactionID: nil, transferID: transfer.id
            ))
        }
        for payment in account.cardPayments where payment.date <= date {
            entries.append(AccountHistoryEntry(id: "card-payment/\(payment.id)", date: payment.date,
                title: "Pagamento de fatura", detail: payment.invoice.card.name,
                amountInCents: payment.amountInCents, isIncoming: false, notes: nil, transactionID: nil, transferID: nil))
        }
        return entries.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date > $1.date }
    }
}
