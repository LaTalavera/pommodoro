import Foundation
import Observation
import Security

/// Un bloque de concentración ya listo para Notion. Se guarda tal cual en la
/// cola de pendientes, así que no depende de SwiftData ni del motor.
struct NotionFocusEntry: Codable, Equatable {
    /// Identifica la sesión en Notion para no duplicarla si un envío se repite.
    var externalID: String
    var title: String
    var startedAt: Date
    var endedAt: Date
    var minutes: Double
    var outcome: SessionOutcome
    var externalInterruptions: Int
    var internalInterruptions: Int

    static let untitled = "Bloque de concentración"

    /// Solo los bloques de concentración van al Focus Log: los descansos no son foco.
    init?(record: SessionRecord) {
        guard record.phase == .work else { return nil }
        externalID = "pommodoro-\(Int(record.startedAt.timeIntervalSince1970))"
        title = record.task ?? Self.untitled
        startedAt = record.startedAt
        endedAt = record.endedAt
        // Una décima de minuto basta; el gráfico de Notion suma minutos.
        minutes = (record.actualSeconds / 6).rounded() / 10
        outcome = record.outcome
        externalInterruptions = record.externalInterruptions
        internalInterruptions = record.internalInterruptions
    }

    /// Cuerpo de `POST /v1/pages`. Los nombres son los de las propiedades del
    /// Focus Log: si se renombran allí, hay que cambiarlos aquí.
    func pageBody(databaseID: String, timeZone: TimeZone = .current) -> [String: Any] {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        return [
            "parent": ["database_id": databaseID],
            "properties": [
                "Sesión": ["title": [["text": ["content": title]]]],
                "Fecha": ["date": [
                    "start": formatter.string(from: startedAt),
                    "end": formatter.string(from: endedAt),
                ]],
                "Minutos": ["number": minutes],
                "Tipo": ["select": ["name": "Deep Work"]],
                "Resultado": ["select": ["name": outcome.title]],
                "Interrupciones": ["number": externalInterruptions + internalInterruptions],
                "Interrupciones externas": ["number": externalInterruptions],
                "Distracciones propias": ["number": internalInterruptions],
                "ID externo": ["rich_text": [["text": ["content": externalID]]]],
                "Origen": ["select": ["name": "Pommodoro"]],
            ],
        ]
    }

    /// Cuerpo de `POST /v1/databases/{id}/query` que encuentra esta sesión si ya se envió.
    var duplicateQueryBody: [String: Any] {
        [
            "filter": ["property": "ID externo", "rich_text": ["equals": externalID]],
            "page_size": 1,
        ]
    }
}

/// Lo único que la sincronización necesita de la red. En los tests se sustituye
/// por una respuesta fija.
protocol NotionTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionNotionTransport: NotionTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// El token de la integración va al llavero, no a `UserDefaults`: es un secreto.
enum NotionCredentials {
    private static let service = "com.pommodoro.app.notion"
    private static let account = "integration-token"

    static var token: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
            guard let newValue, !newValue.isEmpty else { return }
            var attributes = query
            attributes[kSecValueData as String] = Data(newValue.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(attributes as CFDictionary, nil)
        }
    }
}

/// Envía los bloques terminados al Focus Log de Notion. Lo que no se pueda
/// enviar (sin red, Notion caído) queda en cola y se reintenta en el siguiente
/// bloque o al abrir la app; antes de crear cada página se comprueba que no
/// exista ya, así que reintentar nunca duplica.
@MainActor
@Observable
final class NotionSync {
    static let shared = NotionSync()

    enum Status: Equatable {
        case idle
        case syncing
        case synced(Date)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var pending: [NotionFocusEntry]

    private let transport: NotionTransport
    private let store: UserDefaults
    private let settings: AppSettings
    private let tokenProvider: () -> String?
    private var isFlushing = false

    private static let pendingKey = "notionPendingEntries"
    private static let apiVersion = "2022-06-28"

    init(
        transport: NotionTransport = URLSessionNotionTransport(),
        store: UserDefaults = .standard,
        settings: AppSettings = .shared,
        tokenProvider: @escaping () -> String? = { NotionCredentials.token }
    ) {
        self.transport = transport
        self.store = store
        self.settings = settings
        self.tokenProvider = tokenProvider
        if let data = store.data(forKey: Self.pendingKey),
           let saved = try? JSONDecoder().decode([NotionFocusEntry].self, from: data) {
            pending = saved
        } else {
            pending = []
        }
    }

    var isConfigured: Bool {
        settings.notionSyncEnabled && !(tokenProvider() ?? "").isEmpty
            && !settings.notionDatabaseID.isEmpty
    }

    /// Mete el bloque en la cola y lo envía en segundo plano.
    func enqueue(_ record: SessionRecord) {
        guard settings.notionSyncEnabled, let entry = NotionFocusEntry(record: record) else { return }
        if !pending.contains(where: { $0.externalID == entry.externalID }) {
            pending.append(entry)
            savePending()
        }
        Task { await flush() }
    }

    /// Envía todo lo pendiente, en orden. Se para en el primer fallo de red o de
    /// configuración para no martillear la API.
    func flush() async {
        guard isConfigured, !isFlushing, !pending.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }
        status = .syncing

        while let entry = pending.first {
            do {
                if try await !exists(entry) {
                    try await create(entry)
                }
                pending.removeFirst()
                savePending()
            } catch NotionSyncError.rejected(let message) {
                // Notion no aceptará nunca este cuerpo: reintentarlo bloquearía la cola.
                pending.removeFirst()
                savePending()
                status = .failed(message)
                continue
            } catch {
                status = .failed(Self.describe(error))
                return
            }
        }
        status = .synced(Date())
    }

    private func exists(_ entry: NotionFocusEntry) async throws -> Bool {
        let path = "databases/\(settings.notionDatabaseID)/query"
        let data = try await call(path, body: entry.duplicateQueryBody)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return !((json?["results"] as? [Any]) ?? []).isEmpty
    }

    private func create(_ entry: NotionFocusEntry) async throws {
        _ = try await call("pages", body: entry.pageBody(databaseID: settings.notionDatabaseID))
    }

    private func call(_ path: String, body: [String: Any]) async throws -> Data {
        guard let token = tokenProvider(),
              let url = URL(string: "https://api.notion.com/v1/\(path)") else {
            throw NotionSyncError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200..<300:
            return data
        case 400:
            throw NotionSyncError.rejected(Self.message(in: data) ?? "Notion rechazó el bloque.")
        case 401, 403:
            throw NotionSyncError.unauthorized
        case 404:
            throw NotionSyncError.databaseNotShared
        default:
            throw NotionSyncError.server(response.statusCode)
        }
    }

    private func savePending() {
        store.set(try? JSONEncoder().encode(pending), forKey: Self.pendingKey)
    }

    private static func message(in data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["message"] as? String
    }

    private static func describe(_ error: Error) -> String {
        (error as? NotionSyncError)?.description ?? "Sin conexión con Notion. Se reintentará."
    }
}

enum NotionSyncError: Error, CustomStringConvertible {
    case notConfigured
    case unauthorized
    case databaseNotShared
    case rejected(String)
    case server(Int)

    var description: String {
        switch self {
        case .notConfigured: "Falta el token o el ID de la base de datos."
        case .unauthorized: "Token no válido. Revisa la integración de Notion."
        case .databaseNotShared: "La base de datos no existe o no está conectada a la integración."
        case .rejected(let message): message
        case .server(let code): "Notion respondió \(code). Se reintentará."
        }
    }
}

/// Envoltorio del registrador: guarda como siempre y, además, manda los bloques
/// de concentración a Notion. El motor no se entera de que Notion existe.
@MainActor
struct NotionSyncingRecorder: SessionRecording {
    let base: SessionRecording
    let sync: NotionSync

    func record(_ record: SessionRecord) {
        base.record(record)
        sync.enqueue(record)
    }

    func recentTasks(limit: Int) -> [String] {
        base.recentTasks(limit: limit)
    }
}
