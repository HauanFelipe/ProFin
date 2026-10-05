import SwiftUI

struct SpendingAnalysisSections: View {
    let analysis: SpendingAnalysisResult
    let month: Date

    private func signedMoney(_ amount: Int64) -> String {
        (amount > 0 ? "+ " : "") + Money.formatted(amount)
    }

    var body: some View {
        Section {
            LabeledContent("Mês selecionado, após estornos", value: Money.formatted(analysis.total))
            if analysis.refunded > 0 { LabeledContent("Estornos no mês", value: Money.formatted(analysis.refunded)) }
            LabeledContent("Mês anterior", value: Money.formatted(analysis.previousTotal))
            LabeledContent("Variação", value: signedMoney(analysis.total - analysis.previousTotal))
            if analysis.previousTotal > 0 {
                LabeledContent("Variação percentual", value: (Double(analysis.total - analysis.previousTotal) / Double(analysis.previousTotal)).formatted(.percent.precision(.fractionLength(1))))
            } else {
                Text("Sem gastos registrados no mês anterior para calcular a variação percentual.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Comparação entre meses")
        } footer: {
            Text(Calendar.current.isDate(month, equalTo: Date(), toGranularity: .month)
                 ? "Mês atual em andamento comparado ao mês anterior completo. Inclui todas as parcelas já cadastradas para a fatura deste mês."
                 : "Comparação dos meses completos, conforme os registros disponíveis. Ausência de registros não comprova ausência de gastos.")
        }
        Section("Gastos por categoria") {
            if analysis.categories.isEmpty {
                Text("Sem saldo de gastos neste mês.").foregroundStyle(.secondary)
            }
            ForEach(analysis.categories) { category in
                NavigationLink {
                    CategorySpendingView(categoryID: category.id, month: month)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Saldo de gastos com \(category.name) no mês, após estornos: \(Money.formatted(category.amount)).")
                            .font(.subheadline)
                        LabeledContent(category.name, value: Money.formatted(category.amount))
                            .fontWeight(.medium)
                        ProgressView(value: category.share)
                            .accessibilityLabel("Participação de \(category.name)")
                            .accessibilityValue(category.share.formatted(.percent.precision(.fractionLength(1))))
                        Text("\(category.share.formatted(.percent.precision(.fractionLength(1)))) dos saldos positivos · \(category.count) lançamentos")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Mês anterior: \(Money.formatted(category.previousAmount)) · Variação: \(signedMoney(category.change))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let percentage = category.percentageChange {
                            Text("Variação percentual: \(percentage.formatted(.percent.precision(.fractionLength(1))))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Text("Crie categorias como Namorada, Família ou Viagens ao registrar um gasto. Toque em uma categoria para conferir os lançamentos do mês.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        Section {
            LabeledContent("Essenciais", value: Money.formatted(analysis.essential))
            LabeledContent("Não essenciais", value: Money.formatted(analysis.nonEssential))
            if analysis.unclassified > 0 {
                LabeledContent("Sem classificação", value: Money.formatted(analysis.unclassified))
            }
        } header: {
            Text("Classificação dos gastos")
        } footer: {
            Text("Estornos reduzem os gastos no mês da fatura em que o crédito foi lançado; valores negativos indicam crédito. Percentuais por categoria consideram apenas saldos positivos. Usa a classificação que você escolheu. Cada parcela conta como um lançamento; o total da compra e o pagamento da fatura não são somados novamente.")
        }
        Section("Pontos para revisar") {
            if let largest = analysis.categories.first, largest.amount > 0 {
                Text("Maior categoria: \(largest.name), com \(Money.formatted(largest.amount)).")
            }
            if let increase = analysis.largestIncrease {
                Text("Maior aumento em valor: \(increase.name), \(signedMoney(increase.change)) em relação ao mês anterior.")
            }
            if analysis.nonEssential > 0 {
                Text("Você classificou \(Money.formatted(analysis.nonEssential)) como não essenciais. Revise esses lançamentos se quiser liberar dinheiro para suas prioridades.")
            } else {
                Text("Não há gastos classificados como não essenciais neste mês.")
            }
            Text("Esses números não indicam desperdício nem uma economia garantida. A decisão de reduzir um gasto é sua.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}
