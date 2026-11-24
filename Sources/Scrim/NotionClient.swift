import Foundation
import Security
import ScrimCore

/// Where the Notion token lives. The app uses the Keychain; checks use memory so they never read the real token.
protocol NotionTokenStore: AnyObject {
    func token() -> String?
    func setToken(_ token: String?) -> Bool
}

final class KeychainNotionTokenStore: NotionTokenStore {
    /// A Scrim-only item. Tokens kept by earlier apps under other names are never read or changed.
    private let service = "com.satoshi0817.Scrim.notion"
    private let account = "notion-token"
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    func token() -> String? {
        var request = query
        request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    func setToken(_ token: String?) -> Bool {
        SecItemDelete(query as CFDictionary)
        guard let token, !token.isEmpty else { return true }
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        item[kSecAttrLabel as String] = "Scrim Notion token"
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}

final class MemoryNotionTokenStore: NotionTokenStore {
    private var value: String?
    init(_ value: String? = nil) { self.value = value }
    func token() -> String? { value }
    func setToken(_ token: String?) -> Bool { value = token?.isEmpty == true ? nil : token; return true }
}

/// The token store and API host shared by every Notion task panel and the settings page. Used from the main thread.
final class NotionEnvironment {
    /// Until the app finishes launching (and in every verification run) there is no token and no network.
    static var current = NotionEnvironment(tokens: MemoryNotionTokenStore(), baseURL: NotionAPI.baseURL)
    static let tokenChanged = Notification.Name("ScrimNotionTokenChanged")
    let tokens: NotionTokenStore
    let baseURL: URL
    let session: URLSession
    init(tokens: NotionTokenStore, baseURL: URL, session: URLSession = .shared) {
        self.tokens = tokens; self.baseURL = baseURL; self.session = session
    }
    var client: NotionClient { NotionClient(baseURL: baseURL, token: tokens.token(), session: session) }
    var hasToken: Bool { !(tokens.token() ?? "").isEmpty }
    @discardableResult func setToken(_ token: String?) -> Bool {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = tokens.setToken(trimmed?.isEmpty == true ? nil : trimmed)
        NotificationCenter.default.post(name: Self.tokenChanged, object: nil)
        return saved
    }
}

struct NotionClient: Sendable {
    let baseURL: URL
    let token: String?
    let session: URLSession

    func send(_ request: NotionRequest) async throws -> Data {
        guard let token, !token.isEmpty else { throw NotionAPIError.missingToken }
        var attempt = 0
        while true {
            let data: Data, response: URLResponse
            do { (data, response) = try await session.data(for: request.urlRequest(baseURL: baseURL, token: token)) }
            catch { if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }; throw NotionAPIError.network }
            guard let http = response as? HTTPURLResponse else { throw NotionAPIError.invalidResponse }
            if (200..<300).contains(http.statusCode) { return data }
            let failure = NotionResponses.error(status: http.statusCode, data: data, retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
            // One quick retry for rate limits and overload; writes are safe to repeat because they set absolute values,
            // except page creation, which is never retried so a task cannot be added twice.
            guard failure.isRetryable, failure.code != "public_api_request_blocked", attempt == 0,
                  !(request.method == "POST" && request.path == "v1/pages") else { throw failure }
            attempt += 1
            try await Task.sleep(nanoseconds: UInt64(min(10, failure.retryAfter ?? 1) * 1_000_000_000))
        }
    }
    func verify() async throws { _ = try await send(NotionRequests.me()) }
    func search(_ kind: NotionSearchResult.Kind, query: String) async throws -> [NotionSearchResult] {
        try NotionResponses.search(await send(NotionRequests.search(kind, query: query)))
    }
    /// Data sources for a pasted database link or ID. A data source ID (Notion's "Copy data source ID") also works.
    func dataSources(forLinkedID id: String) async throws -> [NotionSearchResult] {
        do { return try NotionResponses.databaseSources(await send(NotionRequests.database(id))) }
        catch let error as NotionAPIError where error.status == 404 || error.status == 400 {
            guard let source = try? await schema(id) else { throw error }
            return [NotionSearchResult(id: source.id, title: source.title, kind: .dataSource)]
        }
    }
    func schema(_ dataSourceID: String) async throws -> NotionDataSourceSchema {
        try NotionResponses.dataSource(await send(NotionRequests.dataSource(dataSourceID)))
    }
    func openTasks(_ mapping: NotionTaskMapping, schema: NotionDataSourceSchema) async throws -> [NotionTask] {
        var tasks: [NotionTask] = [], cursor: String?
        repeat {
            let data = try await send(NotionRequests.openTasks(mapping, schema: schema, cursor: cursor))
            tasks += try NotionResponses.tasks(data, mapping: mapping)
            cursor = NotionResponses.cursor(data)
        } while cursor != nil && tasks.count < NotionAPI.maximumTasks
        return Array(tasks.prefix(NotionAPI.maximumTasks))
    }
    func create(_ mapping: NotionTaskMapping, title: String, due: NotionDate?) async throws -> NotionTask {
        try NotionResponses.task(await send(NotionRequests.createTask(mapping, title: title, due: due)), mapping: mapping)
    }
    func update(_ id: String, _ mapping: NotionTaskMapping, title: String? = nil, due: NotionDate?? = nil,
                completed: Bool? = nil, restoreStatusOptionID: String? = nil, statusOptionID: String? = nil) async throws -> NotionTask {
        let request = NotionRequests.updateTask(id, mapping, title: title, due: due, completed: completed,
                                                restoreStatusOptionID: restoreStatusOptionID, statusOptionID: statusOptionID)
        return try NotionResponses.task(await send(request), mapping: mapping)
    }
    /// Creates the task database under a page and returns a mapping for it.
    func createTaskDatabase(parentPage: String, title: String) async throws -> NotionTaskMapping {
        let id = try NotionResponses.createdDataSourceID(await send(NotionRequests.createTaskDatabase(parentPage: parentPage, title: title)))
        let created = try await schema(id)
        guard let mapping = created.defaultMapping() else { throw NotionAPIError.invalidResponse }
        return mapping
    }
}
