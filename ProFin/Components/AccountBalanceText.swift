import SwiftUI

struct AccountBalanceText: View {
    let account: FinancialAccount

    var body: some View {
        switch Result(catching: { try FinancialSummary.balance(of: account) }) {
        case .success(let amount?):
            Text(Money.formatted(amount))
        case .success(nil):
            Text("Dinheiro na conta não informado").foregroundStyle(.secondary)
        case .failure:
            Text("Saldo indisponível").foregroundStyle(.secondary)
        }
    }
}
