import SwiftUI
import SwiftData

struct SavingsBoxesView: View {
    @Query(sort: \FinancialAccount.name)
    private var accounts: [FinancialAccount]

    private var savingsBoxes: [FinancialAccount] {
        accounts.filter { $0.kind == .savingsBox || $0.kind == .turboBox }
    }

    var body: some View {
        NavigationStack {
            Group {
                if savingsBoxes.isEmpty {
                    ContentUnavailableView(
                        "Nenhuma caixinha cadastrada",
                        systemImage: "archivebox",
                        description: Text("Suas caixinhas aparecerão aqui com seus saldos. O cadastro de caixinhas estará disponível em uma próxima etapa.")
                    )
                } else {
                    List(savingsBoxes) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(account.name, systemImage: account.kind == .turboBox ? "bolt.fill" : "archivebox")
                                .font(.headline)
                            Text(account.kind == .turboBox ? "Caixinha Turbo" : "Caixinha Normal")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            switch Result(catching: { try FinancialSummary.balance(of: account) }) {
                            case .success(let amount?):
                                Text(Money.formatted(amount))
                                    .font(.title3.weight(.semibold))
                            case .success(nil):
                                Text("Saldo inicial não informado")
                                    .foregroundStyle(.secondary)
                            case .failure:
                                Text("Saldo indisponível")
                                    .foregroundStyle(.secondary)
                            }

                            if !account.isActive {
                                Label("Arquivada", systemImage: "archivebox.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Caixinhas")
        }
    }
}
