import SwiftData
import SwiftUI

@main
struct PommodoroApp: App {
    private let container: ModelContainer
    @State private var engine: PomodoroEngine

    init() {
        let container = Self.makeContainer()
        self.container = container
        _engine = State(
            initialValue: PomodoroEngine(
                recorder: SwiftDataSessionRecorder(context: container.mainContext)
            )
        )
    }

    /// El almacén va a una ruta explícita cuyo directorio creamos nosotros:
    /// dejárselo a SwiftData falla si `Application Support` aún no existe.
    /// Si aun así no se puede abrir, se sigue en memoria — perder el historial
    /// es mucho mejor que no arrancar.
    private static func makeContainer() -> ModelContainer {
        #if DEBUG
        // UI tests use a fresh history without touching the person's records.
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let container = try! ModelContainer(
                for: Session.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            if ProcessInfo.processInfo.arguments.contains("--ui-testing-history-fixture") {
                HistoryUITestFixture.insert(into: container.mainContext)
            }
            return container
        }
        #endif
        let fileManager = FileManager.default
        if let support = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            let url = support.appending(path: "Pommodoro.store")
            if let container = try? ModelContainer(
                for: Session.self,
                configurations: ModelConfiguration(url: url)
            ) {
                return container
            }
        }
        do {
            return try ModelContainer(
                for: Session.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("No se pudo crear el almacén del historial: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        // Una sola ventana: hay un único temporizador, y cada ventana
        // duplicaría el sonido, los avisos y el sondeo de Concentración.
        Window("Pommodoro", id: "timer") {
            TimerView()
                .environment(engine)
                .frame(minWidth: 480, minHeight: 640)
        }
        .defaultSize(width: 960, height: 760)
        .modelContainer(container)
        #else
        WindowGroup {
            TimerView()
                .environment(engine)
        }
        .modelContainer(container)
        #endif
    }
}
