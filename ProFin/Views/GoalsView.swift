import SwiftUI
import SwiftData

struct GoalsView: View {
    @Query(sort: \Goal.createdAt, order: .reverse) private var goals: [Goal]
    @State private var showingNewGoal = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProFinIntro(title: "Um passo de cada vez", message: "Escolha seu objetivo e acompanhe o dinheiro guardado para ele.", symbol: "target")
                }
                Section("Metas ativas") {
                    if !goals.contains(where: { !$0.isArchived }) {
                        Text("Crie uma meta e vincule uma caixinha para acompanhar seu progresso.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(goals.filter { !$0.isArchived }) { goal in
                        NavigationLink { GoalDetailView(goalID: goal.id) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(goal.name, systemImage: "target").font(.headline).foregroundStyle(ProFinStyle.blue)
                                Text("Objetivo: \(Money.formatted(goal.targetAmountInCents))").font(.subheadline)
                                GoalProgressView(goal: goal)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                if goals.contains(where: \.isArchived) {
                    Section("Arquivadas") {
                        ForEach(goals.filter(\.isArchived)) { goal in
                            NavigationLink { GoalDetailView(goalID: goal.id) } label: {
                                VStack(alignment: .leading) {
                                    Text(goal.name)
                                    Text(Money.formatted(goal.targetAmountInCents)).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Metas")
            .proFinScreen()
            .toolbar { Button("Nova meta", systemImage: "plus") { showingNewGoal = true } }
            .sheet(isPresented: $showingNewGoal) { GoalFormView() }
        }
    }
}
