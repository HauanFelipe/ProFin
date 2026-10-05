import SwiftUI
import SwiftData

@main
struct ProFinApp: App {
    @State private var modelContainer: ModelContainer?
    @State private var modelContext: ModelContext?
    @State private var initializationFailed = false
    @State private var sessionID = UUID()
    @State private var restoredBackup = false

    var body: some Scene {
        WindowGroup {
            Group {
                if let modelContainer, let modelContext {
                    MainTabView()
                        .id(sessionID)
                        .environment(\.modelContext, modelContext)
                        .modelContainer(modelContainer)
                } else if initializationFailed {
                    ContentUnavailableView {
                        Label("Não foi possível abrir seus dados", systemImage: "externaldrive.badge.exclamationmark")
                    } description: {
                        Text("Tente novamente. Os dados existentes não serão apagados.")
                    } actions: {
                        Button("Tentar novamente", action: loadData)
                    }
                } else {
                    ProgressView("Abrindo ProFin…")
                }
            }
            .environment(\.locale, Locale(identifier: "pt_BR"))
            .preferredColorScheme(.dark)
            .tint(ProFinStyle.blue)
            .onReceive(NotificationCenter.default.publisher(for: AppData.contextDiscarded)) { notification in
                guard let discarded = notification.object as? ModelContext,
                      discarded === modelContext,
                      let modelContainer else { return }
                modelContext = AppData.makeContext(for: modelContainer)
            }
            .onReceive(NotificationCenter.default.publisher(for: BackupService.restored)) { notification in
                guard let restored = notification.object as? ModelContainer else { return }
                modelContainer = restored
                modelContext = AppData.makeContext(for: restored)
                sessionID = UUID()
                restoredBackup = true
            }
            .alert("Backup restaurado", isPresented: $restoredBackup) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Seus dados foram carregados. Confira os saldos e o histórico no Dashboard.")
            }
            .task {
                if modelContainer == nil && !initializationFailed {
                    loadData()
                }
            }
        }
    }

    private func loadData() {
        do {
            // Testes hospedados no app usam seus próprios bancos temporários.
            // A inicialização da interface não deve migrar o banco do simulador.
            let isRunningUnitTests = NSClassFromString("XCTestCase") != nil
            modelContainer = try AppData.makeContainer(at: isRunningUnitTests ? nil : BackupService.activeStoreURL(), inMemory: isRunningUnitTests)
            if let modelContainer {
                modelContext = AppData.makeContext(for: modelContainer)
            }
            initializationFailed = false
        } catch {
            initializationFailed = true
        }
    }
}
