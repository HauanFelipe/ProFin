import SwiftUI
import SwiftData

struct RecurringExpensesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \RecurringExpense.title) private var expenses: [RecurringExpense]
    @Query(sort: \RecurringExpenseOccurrence.dueDate) private var occurrences: [RecurringExpenseOccurrence]
    @Query private var transactions: [FinancialTransaction]
    @State private var selectedMonth = Calendar.current.dateInterval(of: .month, for: Date())?.start ?? Date()
    @State private var referenceDate = Date()
    @State private var showingForm = false
    @State private var payment: PaymentSelection?
    @State private var generationFailed = false

    private struct PaymentSelection: Identifiable { let id: UUID }

    private var monthData: Result<([RecurringCharge], RecurringMonthlySummary), Error> {
        Result {
            let charges = try RecurringExpenseSummary.charges(
                expenses: expenses, occurrences: occurrences, monthContaining: selectedMonth, now: referenceDate
            )
            let summary = try RecurringExpenseSummary.monthlySummary(
                charges: charges, transactions: transactions, monthContaining: selectedMonth
            )
            return (charges, summary)
        }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RecurringExpenseListView()
                } label: {
                    Label("Gerenciar contas", systemImage: "slider.horizontal.3")
                }
                HStack {
                    Button("Mês anterior", systemImage: "chevron.left") { moveMonth(-1) }
                        .labelStyle(.iconOnly)
                    Spacer()
                    Text(selectedMonth, format: .dateTime.month(.wide).year())
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Spacer()
                    Button("Próximo mês", systemImage: "chevron.right") { moveMonth(1) }
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
            }

            if generationFailed {
                Section {
                    Text("Não foi possível atualizar as cobranças. Os totais podem estar incompletos.")
                    Button("Tentar novamente", action: refresh)
                }
            } else {
                switch monthData {
                case .success(let (charges, summary)):
                    RecurringSummarySection(summary: summary)
                    let upcoming = summary.unpaidCharges.filter {
                        Calendar.current.startOfDay(for: $0.dueDate) >= Calendar.current.startOfDay(for: referenceDate)
                    }
                    if !upcoming.isEmpty {
                        Section("Próximas a vencer neste mês") {
                            ForEach(upcoming.prefix(3)) { charge in
                                LabeledContent(charge.title) {
                                    Text(charge.dueDate, format: .dateTime.day().month())
                                }
                            }
                        }
                    }
                    Section("Cobranças do mês") {
                        if charges.isEmpty {
                            Text("Nenhuma conta prevista para este mês.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(charges) { charge in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(charge.title).font(.headline)
                                Text("\(charge.categoryName) · \(charge.amountType.title)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Text(charge.dueDate, format: .dateTime.day().month(.wide).year())
                                Text("Previsto: \(charge.expectedAmountInCents.map(Money.formatted) ?? "Sem estimativa")")
                                Label(charge.status(asOf: referenceDate).rawValue, systemImage: statusIcon(charge))
                                    .font(.subheadline.weight(.medium))
                                if let paid = charge.paidAmountInCents {
                                    Text("Pago: \(Money.formatted(paid))")
                                    if let transaction = occurrences.first(where: { $0.id == charge.occurrenceID })?.paymentTransaction {
                                        NavigationLink("Ver pagamento") {
                                            TransactionDetailView(transaction: transaction)
                                        }
                                    }
                                } else if let cardAmount = charge.cardAmountInCents {
                                    Text("No cartão: \(Money.formatted(cardAmount)). Consulte as faturas para acompanhar o pagamento.")
                                    if let purchase = occurrences.first(where: { $0.id == charge.occurrenceID })?.cardPurchase {
                                        NavigationLink("Ver compra no cartão") { CardPurchaseDetailView(purchaseID: purchase.id) }
                                    }
                                } else if let id = charge.occurrenceID {
                                    Button("Registrar pagamento") { payment = PaymentSelection(id: id) }
                                        .buttonStyle(.bordered)
                                } else {
                                    Text("Projeção. A cobrança estará disponível no mês correspondente.")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                case .failure:
                    Section {
                        Text("Não foi possível calcular este mês. Verifique os valores cadastrados.")
                    }
                }
            }
        }
        .navigationTitle("Contas recorrentes")
        .proFinScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Nova conta recorrente", systemImage: "plus") { showingForm = true }
            }
        }
        .sheet(isPresented: $showingForm) { RecurringExpenseFormView() }
        .sheet(item: $payment) { selection in RecurringPaymentView(occurrenceID: selection.id) }
        .task { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        referenceDate = Date()
        do {
            try RecurringExpenseOperations.generateDueOccurrences(now: referenceDate, in: context)
            generationFailed = false
        } catch {
            generationFailed = true
        }
    }

    private func moveMonth(_ offset: Int) {
        if let month = Calendar.current.date(byAdding: .month, value: offset, to: selectedMonth) {
            selectedMonth = month
        }
        refresh()
    }

    private func statusIcon(_ charge: RecurringCharge) -> String {
        switch charge.status(asOf: referenceDate) {
        case .onCard: "creditcard"
        case .paid: "checkmark.circle"
        case .overdue: "exclamationmark.circle"
        case .dueSoon: "clock.badge.exclamationmark"
        case .pending: "clock"
        }
    }
}

private struct RecurringSummarySection: View {
    let summary: RecurringMonthlySummary

    var body: some View {
        Section {
            LabeledContent("Previsto no mês", value: summary.expectedInCents.map(Money.formatted) ?? "Incompleto")
            if summary.missingEstimateCount > 0 {
                Text("Subtotal conhecido: \(Money.formatted(summary.knownExpectedInCents)). Contas sem estimativa: \(summary.missingEstimateCount).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("Já pago", value: Money.formatted(summary.paidInCents))
            LabeledContent("Ainda pendente", value: summary.pendingInCents.map(Money.formatted) ?? "Incompleto")
            if summary.pendingWithoutEstimateCount > 0 {
                Text("Pendente conhecido: \(Money.formatted(summary.knownPendingInCents)). Sem estimativa: \(summary.pendingWithoutEstimateCount).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            LabeledContent("Receitas do mês", value: Money.formatted(summary.incomeInCents))
            LabeledContent("Renda comprometida") {
                if let percentage = summary.committedIncomePercentage {
                    Text("\(percentage.formatted(.number.precision(.fractionLength(0...1))))%")
                } else {
                    Text("Indisponível")
                }
            }
        } header: {
            Text("Resumo das recorrências")
        } footer: {
            Text("Comprometimento = previsto recorrente ÷ receitas registradas no mês × 100. Sem receitas ou com estimativas faltantes, o percentual fica indisponível. O pago pertence às cobranças deste mês; a despesa realizada entra no mês do pagamento.")
        }
    }
}
