import SwiftUI

struct GoalProgressView: View {
    let goal: Goal

    var body: some View {
        switch Result(catching: { try GoalSummary.progress(for: goal) }) {
        case .success(.available(let balance, let remaining, let fraction)):
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Money.formatted(balance)) de \(Money.formatted(goal.targetAmountInCents))")
                ProgressView(value: fraction)
                    .accessibilityLabel("Progresso da meta")
                    .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
                Text(remaining == 0 ? "Valor atingido" : "\(fraction.formatted(.percent.precision(.fractionLength(0)))) · Faltam \(Money.formatted(remaining))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        case .success(.unlinked):
            Text("Sem caixinha vinculada").foregroundStyle(.secondary)
        case .success(.unknownBalance):
            Text("Informe quanto dinheiro há na caixinha para calcular o progresso.").foregroundStyle(.secondary)
        case .success(.unavailableAccount):
            Text("Caixinha indisponível. Edite o vínculo da meta.").foregroundStyle(.secondary)
        case .success(.archived):
            Text("Arquivada · não reserva uma caixinha").foregroundStyle(.secondary)
        case .failure:
            Text("Não foi possível calcular o progresso.").foregroundStyle(.secondary)
        }
    }
}
