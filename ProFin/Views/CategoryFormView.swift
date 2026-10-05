import SwiftUI
import SwiftData

struct CategoryFormView: View {
    let onCreated: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome da categoria", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit(save)
                } footer: {
                    Text("A categoria ficará disponível para receitas, despesas e contas recorrentes.")
                }
            }
            .navigationTitle("Nova categoria")
            .proFinScreen()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar", action: save).disabled(!canSave)
                }
            }
            .task { isNameFocused = true }
            .alert("Não foi possível criar a categoria", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() {
        guard canSave else { return }
        do {
            let category = try FinancialOperations.createCategory(name: name, in: context)
            onCreated(category.id)
            dismiss()
        } catch FinancialOperationError.emptyCategoryName {
            errorMessage = "Informe um nome para a categoria."
        } catch FinancialOperationError.duplicateCategoryName {
            errorMessage = "Já existe uma categoria com esse nome. Escolha outro nome ou selecione a categoria existente."
        } catch {
            errorMessage = "Tente novamente. O nome digitado foi mantido."
        }
    }
}
