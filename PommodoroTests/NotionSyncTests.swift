import Foundation
import Testing

@testable import Pommodoro

/// Responde con lo que se le programe y apunta cada petición.
final class FakeNotionTransport: NotionTransport, @unchecked Sendable {
    var responses: [(status: Int, body: String)] = []
    var failWithNetworkError = false
    private(set) var requests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if failWithNetworkError { throw URLError(.notConnectedToInternet) }
        let next = responses.isEmpty ? (200, "{\"results\":[]}") : responses.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0,
                                       httpVersion: nil, headerFields: nil)!
        return (Data(next.1.utf8), response)
    }

    var paths: [String] { requests.map { $0.url!.path } }
}

@MainActor
@Suite("Sincronización con el Focus Log de Notion")
struct NotionSyncTests {
    private let start = Date(timeIntervalSince1970: 1_699_953_200)
    private let noResults = (200, "{\"results\":[]}")
    private let created = (200, "{\"object\":\"page\"}")

    private func record(phase: PomodoroPhase = .work, outcome: SessionOutcome = .completed,
                        seconds: Double = 3000, task: String? = "Migración VPC",
                        offset: TimeInterval = 0) -> SessionRecord {
        SessionRecord(startedAt: start + offset, endedAt: start + offset + seconds, phase: phase,
                      outcome: outcome, plannedSeconds: 3000, actualSeconds: seconds, task: task,
                      externalInterruptions: 1, internalInterruptions: 2)
    }

    private func makeSync(_ transport: FakeNotionTransport, enabled: Bool = true,
                          token: String? = "ntn_test") -> (NotionSync, UserDefaults) {
        let store = UserDefaults(suiteName: "NotionSyncTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: store)
        settings.notionSyncEnabled = enabled
        let sync = NotionSync(transport: transport, store: store, settings: settings,
                              tokenProvider: { token })
        return (sync, store)
    }

    @Test("Los descansos no son foco y no se envían")
    func breaksAreSkipped() {
        #expect(NotionFocusEntry(record: record(phase: .shortBreak)) == nil)
        #expect(NotionFocusEntry(record: record(phase: .longBreak)) == nil)
        #expect(NotionFocusEntry(record: record()) != nil)
    }

    @Test("El cuerpo usa los nombres de las propiedades del Focus Log")
    func pageBody() throws {
        let entry = try #require(NotionFocusEntry(record: record(outcome: .abandoned, seconds: 1234)))
        let body = entry.pageBody(databaseID: "db123", timeZone: TimeZone(secondsFromGMT: 0)!)
        let properties = try #require(body["properties"] as? [String: Any])

        #expect((body["parent"] as? [String: String])?["database_id"] == "db123")
        #expect(properties["Minutos"] as? [String: Double] == ["number": 20.6])
        #expect(properties["Interrupciones"] as? [String: Int] == ["number": 3])
        #expect(properties["Interrupciones externas"] as? [String: Int] == ["number": 1])
        #expect(properties["Distracciones propias"] as? [String: Int] == ["number": 2])
        let result = properties["Resultado"] as? [String: [String: String]]
        #expect(result?["select"]?["name"] == "Abandonado")
        let date = properties["Fecha"] as? [String: [String: String]]
        #expect(date?["date"]?["start"] == "2023-11-14T09:13:20Z")
        #expect(entry.externalID == "pommodoro-1699953200")
        // Debe poder serializarse tal cual.
        _ = try JSONSerialization.data(withJSONObject: body)
    }

    @Test("Un bloque sin tarea recibe un título genérico")
    func untitledBlock() throws {
        let entry = try #require(NotionFocusEntry(record: record(task: nil)))
        #expect(entry.title == NotionFocusEntry.untitled)
    }

    @Test("Comprueba duplicados y crea la página con las cabeceras de la API")
    func flushCreatesPage() async throws {
        let transport = FakeNotionTransport()
        transport.responses = [noResults, created]
        let (sync, _) = makeSync(transport)

        sync.enqueue(record())
        await sync.flush()

        #expect(transport.paths == [
            "/v1/databases/\(AppSettings.defaultNotionDatabaseID)/query", "/v1/pages",
        ])
        let request = try #require(transport.requests.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ntn_test")
        #expect(request.value(forHTTPHeaderField: "Notion-Version") == "2022-06-28")
        #expect(sync.pending.isEmpty)
    }

    @Test("Si la sesión ya está en Notion no se vuelve a crear")
    func duplicatesAreNotCreated() async {
        let transport = FakeNotionTransport()
        transport.responses = [(200, "{\"results\":[{\"id\":\"x\"}]}")]
        let (sync, _) = makeSync(transport)

        sync.enqueue(record())
        await sync.flush()

        #expect(transport.paths.allSatisfy { $0.hasSuffix("/query") })
        #expect(sync.pending.isEmpty)
    }

    @Test("Sin red el bloque queda en cola, sobrevive a reiniciar y se envía después")
    func offlineQueue() async {
        let transport = FakeNotionTransport()
        transport.failWithNetworkError = true
        let (sync, store) = makeSync(transport)

        sync.enqueue(record())
        await sync.flush()
        #expect(sync.pending.count == 1)
        if case .failed = sync.status {} else { Issue.record("Debería informar del fallo") }

        // Nueva instancia sobre el mismo almacén: como al reabrir la app.
        transport.failWithNetworkError = false
        transport.responses = [noResults, created]
        let settings = AppSettings(defaults: store)
        let reopened = NotionSync(transport: transport, store: store, settings: settings,
                                  tokenProvider: { "ntn_test" })
        #expect(reopened.pending.count == 1)
        await reopened.flush()
        #expect(reopened.pending.isEmpty)
    }

    @Test("Un cuerpo rechazado (400) se descarta para no bloquear la cola")
    func rejectedEntryIsDropped() async {
        let transport = FakeNotionTransport()
        transport.responses = [
            noResults, (400, "{\"message\":\"Resultado is not a property\"}"),
            noResults, created,
        ]
        let (sync, _) = makeSync(transport)

        sync.enqueue(record())
        sync.enqueue(record(offset: 4000))
        await sync.flush()

        #expect(sync.pending.isEmpty)
        #expect(transport.paths.filter { $0 == "/v1/pages" }.count == 2)
    }

    @Test("Un token inválido deja todo en cola")
    func unauthorizedKeepsQueue() async {
        let transport = FakeNotionTransport()
        transport.responses = [(401, "{}")]
        let (sync, _) = makeSync(transport)

        sync.enqueue(record())
        await sync.flush()

        #expect(sync.pending.count == 1)
        #expect(sync.status == .failed(NotionSyncError.unauthorized.description))
    }

    @Test("Con la sincronización apagada no se encola ni se llama a la red")
    func disabledDoesNothing() async {
        let transport = FakeNotionTransport()
        let (sync, _) = makeSync(transport, enabled: false)

        sync.enqueue(record())
        await sync.flush()

        #expect(sync.pending.isEmpty)
        #expect(transport.requests.isEmpty)
    }

    @Test("El registrador guarda siempre en local además de encolar")
    func recorderKeepsLocalHistory() {
        let transport = FakeNotionTransport()
        let (sync, _) = makeSync(transport, enabled: false)
        let spy = SpyRecorder()
        let recorder = NotionSyncingRecorder(base: spy, sync: sync)

        recorder.record(record())
        recorder.record(record(phase: .shortBreak))

        #expect(spy.records.count == 2)
    }
}
