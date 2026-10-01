import SwiftUI

struct CreateCategoryButton: View {
    @Binding var selection: UUID?
    @State private var showingForm = false

    var body: some View {
        Button("Criar categoria", systemImage: "plus.circle") {
            showingForm = true
        }
        .sheet(isPresented: $showingForm) {
            CategoryFormView { categoryID in
                selection = categoryID
            }
        }
    }
}
