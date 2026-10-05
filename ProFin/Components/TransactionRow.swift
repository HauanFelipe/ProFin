import SwiftUI

struct TransactionRow: View {
    let transaction: FinancialTransaction
    private var incoming: Bool { transaction.type == .income }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: incoming ? "arrow.down.left" : "arrow.up.right")
                .font(.headline)
                .foregroundStyle(incoming ? ProFinStyle.blue : Color.primary)
                .frame(width: 36, height: 36)
                .background(ProFinStyle.blue.opacity(incoming ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(transaction.title).font(.headline)
                Text("\(incoming ? "+" : "−") \(Money.formatted(transaction.amountInCents))")
                    .font(.headline).monospacedDigit()
                    .foregroundStyle(incoming ? ProFinStyle.blue : Color.primary)
                Text("\(transaction.type.title) · \(transaction.category.name)")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(transaction.date, format: .dateTime.day().month(.wide).year())
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
