import SwiftUI

struct TransactionRow: View {
    let transaction: FinancialTransaction

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transaction.title)
                .font(.headline)

            Text("\(transaction.type == .income ? "+" : "−") \(Money.formatted(transaction.amountInCents))")
                .font(.headline)
                .foregroundStyle(transaction.type == .income ? Color.green : Color.primary)

            Text("\(transaction.type.title) · \(transaction.category.name)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(transaction.date, format: .dateTime.day().month(.wide).year())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
