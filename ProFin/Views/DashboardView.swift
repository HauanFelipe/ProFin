import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var refunds: [CardRefund]
    @Query private var installments: [CardInstallment]
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @State private var refreshed = false
    @State private var showingTransaction = false
    @Query(sort: \FinancialAccount.name)
    private var accounts: [FinancialAccount]
    @Query(sort: \FinancialTransaction.date, order: .reverse)
    private var transactions: [FinancialTransaction]
    @Query private var invoices: [CardInvoice]
    @State private var referenceDate = Date()

    private func netWorth() throws -> Int64? {
        guard let assets = try FinancialSummary.netWorth(accounts: accounts, asOf: referenceDate) else { return nil }
        return try FinancialSummary.cents(Decimal(assets) - Decimal(CreditCardService.debt(invoices, asOf: referenceDate)) + Decimal(CreditCardService.creditBalance(invoices, asOf: referenceDate)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProFinIntro(title: "Seu dinheiro, com clareza", message: referenceDate.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "pt_BR"))), symbol: "chart.line.uptrend.xyaxis")
                }
                Section {
                    switch Result(catching: { try FinancialSummary.availableMoney(accounts: accounts) }) {
                    case .success(let amount?):
                        ProFinBalanceCard(title: "Dinheiro nas contas", value: Money.formatted(amount),
                            explanation: "Fora das caixinhas. As contas a pagar ainda não foram descontadas.", symbol: "wallet.bifold")
                    case .success(nil):
                        ProFinBalanceCard(title: "Dinheiro nas contas", value: "Vamos começar?",
                            explanation: "Informe quanto você tem hoje nas suas contas.", symbol: "wallet.bifold")
                    case .failure:
                        Text("Não foi possível calcular o dinheiro nas contas.")
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                Section("Acesso rápido") {
                    Button { showingTransaction = true } label: {
                        ProFinFeatureLabel(title: "Registrar movimentação", subtitle: "Recebeu ou gastou? Registre aqui.", symbol: "plus.circle.fill")
                    }
                    NavigationLink { CreditCardsView() } label: {
                        ProFinFeatureLabel(title: "Cartões e faturas", subtitle: "Compras, parcelas e pagamentos", symbol: "creditcard.fill")
                    }
                    NavigationLink { AccountsView() } label: {
                        ProFinFeatureLabel(title: "Dinheiro nas contas", subtitle: "Confira ou atualize seus saldos", symbol: "wallet.bifold.fill")
                    }
                }

                DashboardPlanningSections(now: referenceDate, refreshed: refreshed, retry: refresh)

                Section {
                    if let credit = try? CreditCardService.creditBalance(invoices), credit > 0 {
                        LabeledContent("Crédito restante nos cartões", value: Money.formatted(credit))
                        Text("Incluído no patrimônio, mas não no dinheiro disponível para transferir.").font(.caption)
                    }
                    if let debt = try? CreditCardService.debt(invoices) {
                        LabeledContent("Dívida total nos cartões", value: Money.formatted(debt))
                    }
                }
                Section("Patrimônio líquido") {
                    switch Result(catching: { try netWorth() }) {
                    case .success(let amount?):
                        Text(Money.formatted(amount))
                            .font(.title.bold())
                            .contentTransition(.numericText())
                    case .success(nil):
                        Label("Patrimônio incompleto", systemImage: "info.circle")
                            .font(.headline)
                        Text("Informe quanto dinheiro há nas contas e caixinhas ativas para calcular o patrimônio.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    case .failure:
                        Label("Não foi possível calcular o patrimônio.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }

                MonthlySummarySection(transactions: transactions, month: referenceDate)

                spendingSection
                goalsSection

                Section {
                    NavigationLink { BackupView() } label: {
                        ProFinFeatureLabel(title: "Backup e restauração", subtitle: "Guarde uma cópia dos seus dados", symbol: "externaldrive.fill")
                    }
                }

                Section("Últimas movimentações") {
                    if transactions.isEmpty {
                        Text("Registre sua primeira receita ou despesa na aba Movimentações.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(transactions.prefix(5)) { transaction in
                            NavigationLink {
                                TransactionDetailView(transaction: transaction)
                            } label: {
                                TransactionRow(transaction: transaction)
                            }
                        }
                    }
                }
            }
            .navigationTitle("ProFin")
            .proFinScreen()
            .sheet(isPresented: $showingTransaction) { TransactionFormView() }
            .onAppear(perform: refresh)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .refreshable { refresh() }
        }
    }

    private var spendingSection: some View {
        Section("Maior categoria de gasto") {
            switch Result(catching: { try SpendingAnalysis.calculate(transactions: transactions,
                installments: installments, month: referenceDate, refunds: refunds, now: referenceDate) }) {
            case .success(let analysis):
                if let category = analysis.categories.first, category.amount > 0 {
                    NavigationLink {
                        CategorySpendingView(categoryID: category.id, month: referenceDate)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            LabeledContent(category.name, value: Money.formatted(category.amount))
                            Text("\(category.share.formatted(.percent.precision(.fractionLength(1)))) dos saldos positivos por categoria neste mês")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Nenhum gasto registrado neste mês.")
                }
            case .failure:
                Text("Não foi possível calcular os gastos por categoria.")
            }
        }
    }

    private var goalsSection: some View {
        Section {
            let active = goals.filter { !$0.isArchived }
            if active.isEmpty {
                Text("Crie uma meta na aba Metas para acompanhar seu progresso aqui.")
            }
            ForEach(active.prefix(3)) { goal in
                NavigationLink { GoalDetailView(goalID: goal.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(goal.name).font(.headline)
                        GoalProgressView(goal: goal)
                    }
                }
            }
        } header: {
            Text("Metas em andamento")
        } footer: {
            Text("Até três metas ativas mais recentes. O saldo da caixinha indica o progresso, mas não garante que a compra caiba no orçamento.")
        }
    }

    private func refresh() {
        referenceDate = Date()
        do {
            try RecurringExpenseOperations.generateDueOccurrences(in: context)
            refreshed = true
        } catch {
            refreshed = false
        }
    }

}
