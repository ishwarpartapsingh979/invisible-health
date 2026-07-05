//
//  OpenWearablesManager.swift
//  Invisible_Health
//
//  Talks to the self-hosted Open Wearables backend
//  (https://github.com/the-momentum/open-wearables)
//
//  Auth model: one API key per app (header X-Open-Wearables-API-Key).
//  Each end-user is represented by a UUID in OW that we store in keychain.
//  Whoop OAuth is handled server-side by OW; the iOS app just opens the
//  authorization URL in ASWebAuthenticationSession and polls for the
//  resulting connection.
//

import Foundation
import SwiftUI
import AuthenticationServices

class OpenWearablesManager: NSObject, ObservableObject {
    static let shared = OpenWearablesManager()

    // MARK: - Published state
    @Published var isConfigured = false   // has API key + user_id
    @Published var isWhoopConnected = false
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: String?

    @Published var whoopRecovery: WhoopRecovery?
    @Published var whoopStrain: WhoopStrain?
    @Published var whoopSleep: WhoopSleep?
    @Published var whoopWorkouts: [WhoopActivity] = []   // discrete activities (last few days)

    // MARK: - Credentials (keychain-backed)
    var apiKey: String? {
        get { KeychainHelper.load(key: OpenWearablesKeys.apiKey) }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainHelper.save(key: OpenWearablesKeys.apiKey, data: v)
            } else {
                KeychainHelper.delete(key: OpenWearablesKeys.apiKey)
            }
            refreshConfiguredState()
        }
    }

    var userId: String? {
        get { KeychainHelper.load(key: OpenWearablesKeys.userId) }
        set {
            if let v = newValue, !v.isEmpty {
                KeychainHelper.save(key: OpenWearablesKeys.userId, data: v)
            } else {
                KeychainHelper.delete(key: OpenWearablesKeys.userId)
            }
            refreshConfiguredState()
        }
    }

    // MARK: - Private
    private let session = URLSession.shared
    private var syncTimer: Timer?
    private var authSession: ASWebAuthenticationSession?

    private lazy var jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    override init() {
        super.init()
        refreshConfiguredState()
        if isConfigured {
            checkConnectionStatus()
            startPeriodicSync()
        }
    }

    private func refreshConfiguredState() {
        DispatchQueue.main.async {
            self.isConfigured = (self.apiKey?.isEmpty == false) && (self.userId?.isEmpty == false)
        }
    }

    // MARK: - Request helper
    private func makeRequest(path: String, method: String = "GET", body: Data? = nil) -> URLRequest? {
        guard let key = apiKey, !key.isEmpty else { return nil }
        guard let url = URL(string: "\(OpenWearablesConfig.baseURL)\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(key, forHTTPHeaderField: "X-Open-Wearables-API-Key")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        return req
    }

    private func perform<T: Decodable>(_ req: URLRequest, decode: T.Type, completion: @escaping (T?) -> Void) {
        session.dataTask(with: req) { [weak self] data, response, error in
            if let error = error {
                print("OW request error \(req.url?.path ?? ""): \(error)")
                completion(nil); return
            }
            guard let data = data else { completion(nil); return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(400) ?? ""
                print("OW \(http.statusCode) on \(req.url?.path ?? ""): \(bodyPreview)")
                completion(nil); return
            }
            do {
                let decoded = try self?.jsonDecoder.decode(T.self, from: data)
                completion(decoded)
            } catch {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(800) ?? ""
                print("OW decode error \(T.self) on \(req.url?.path ?? ""): \(error)\nBody: \(bodyPreview)")
                completion(nil)
            }
        }.resume()
    }

    // MARK: - Connection status
    func checkConnectionStatus(completion: (() -> Void)? = nil) {
        guard let uid = userId, !uid.isEmpty,
              let req = makeRequest(path: OpenWearablesConfig.Endpoints.connections(userId: uid)) else {
            DispatchQueue.main.async { self.isWhoopConnected = false; completion?() }
            return
        }
        perform(req, decode: [Connection].self) { [weak self] connections in
            let connected = connections?.contains(where: {
                $0.provider.lowercased() == "whoop" && ($0.status?.lowercased() == "active")
            }) ?? false
            DispatchQueue.main.async { self?.isWhoopConnected = connected; completion?() }
        }
    }

    // MARK: - Whoop OAuth (server-side via OW)
    func connectWhoop() {
        guard let uid = userId, !uid.isEmpty,
              let req = makeRequest(path: OpenWearablesConfig.Endpoints.authorizeWhoop(userId: uid)) else {
            DispatchQueue.main.async { self.syncError = "Set up API key and user ID first" }
            return
        }
        perform(req, decode: AuthorizeResponse.self) { [weak self] resp in
            guard let urlStr = resp?.authorizationUrl, let url = URL(string: urlStr) else {
                DispatchQueue.main.async { self?.syncError = "Could not get Whoop authorization URL" }
                return
            }
            DispatchQueue.main.async { self?.openAuthSession(url: url) }
        }
    }

    private func openAuthSession(url: URL) {
        // OW handles the OAuth callback server-side, so there's no app-side
        // scheme to match. We pass a dummy scheme and treat session dismissal
        // (success or cancel) as "check status now."
        let auth = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "invisiblehealth"
        ) { [weak self] _, _ in
            // Either the user finished and closed the sheet, or they cancelled.
            // Re-check connection state from OW.
            self?.checkConnectionStatus()
            // Give backend a moment then trigger a first sync.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self?.triggerProviderSync()
                self?.performSync()
            }
        }
        auth.presentationContextProvider = self
        auth.prefersEphemeralWebBrowserSession = false
        authSession = auth
        auth.start()
    }

    // MARK: - Data fetch
    /// Default fetch window for "today's metrics": last 2 days so we catch the
    /// most recently produced daily summary even across timezones.
    private func defaultDateRange() -> (start: String, end: String) {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        let now = Date()
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        return (f.string(from: twoDaysAgo), f.string(from: now))
    }

    func fetchWhoopRecovery(completion: @escaping (WhoopRecovery?) -> Void) {
        guard let uid = userId else { completion(nil); return }
        let r = defaultDateRange()
        guard let req = makeRequest(path: OpenWearablesConfig.Endpoints.recoverySummary(userId: uid, startDate: r.start, endDate: r.end)) else {
            completion(nil); return
        }
        fetchLatest(req, completion: completion)
    }

    func fetchWhoopStrain(completion: @escaping (WhoopStrain?) -> Void) {
        guard let uid = userId else { completion(nil); return }
        let r = defaultDateRange()
        guard let req = makeRequest(path: OpenWearablesConfig.Endpoints.activitySummary(userId: uid, startDate: r.start, endDate: r.end)) else {
            completion(nil); return
        }
        fetchLatest(req, completion: completion)
    }

    /// Discrete Whoop activities (running/walking/etc.) over the last several
    /// days. Returns the whole list (not just the latest), newest first.
    func fetchWhoopWorkouts(completion: @escaping ([WhoopActivity]) -> Void) {
        guard let uid = userId else { completion([]); return }
        let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
        let now = Date()
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let path = OpenWearablesConfig.Endpoints.workoutEvents(
            userId: uid, startDate: f.string(from: weekAgo), endDate: f.string(from: now))
        guard let req = makeRequest(path: path) else { completion([]); return }
        fetchList(req) { (items: [WhoopActivity]) in
            // Newest first by start time.
            completion(items.sorted { ($0.startTime ?? "") > ($1.startTime ?? "") })
        }
    }

    /// Like fetchLatest, but returns the full decoded list from a paginated or
    /// bare-array response.
    private func fetchList<T: Decodable>(_ req: URLRequest, completion: @escaping ([T]) -> Void) {
        session.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { completion([]); return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                completion([]); return
            }
            if let page = try? self.jsonDecoder.decode(PageResponse<T>.self, from: data) {
                completion(page.data)
            } else if let array = try? self.jsonDecoder.decode([T].self, from: data) {
                completion(array)
            } else {
                completion([])
            }
        }.resume()
    }

    func fetchWhoopSleep(completion: @escaping (WhoopSleep?) -> Void) {
        guard let uid = userId else { completion(nil); return }
        let r = defaultDateRange()
        guard let req = makeRequest(path: OpenWearablesConfig.Endpoints.sleepSummary(userId: uid, startDate: r.start, endDate: r.end)) else {
            completion(nil); return
        }
        fetchLatest(req, completion: completion)
    }

    /// OW summary endpoints return a paginated wrapper `{data: [...], pagination, metadata}`
    /// with records sorted oldest-first. We decode and then pick the MOST RECENT item
    /// by `date` (descending). Falls back to a bare `[T]` shape if the wrapper isn't present.
    private func fetchLatest<T: Decodable>(_ req: URLRequest, completion: @escaping (T?) -> Void) {
        session.dataTask(with: req) { [weak self] data, response, error in
            guard let self = self else { completion(nil); return }
            if let error = error {
                print("OW request error \(req.url?.path ?? ""): \(error)")
                completion(nil); return
            }
            guard let data = data else { completion(nil); return }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(400) ?? ""
                print("OW \(http.statusCode) on \(req.url?.path ?? ""): \(bodyPreview)")
                completion(nil); return
            }

            let path = req.url?.path ?? ""

            // Pull the records out of either shape.
            var items: [T] = []
            if let page = try? self.jsonDecoder.decode(PageResponse<T>.self, from: data) {
                items = page.data
                print("OW decoded \(T.self) via PageResponse (count=\(items.count)) on \(path)")
            } else if let array = try? self.jsonDecoder.decode([T].self, from: data) {
                items = array
                print("OW decoded \(T.self) via bare array (count=\(items.count)) on \(path)")
            } else {
                let bodyPreview = String(data: data, encoding: .utf8)?.prefix(800) ?? ""
                print("OW could not decode \(T.self) on \(path). Body: \(bodyPreview)")
                completion(nil); return
            }

            // Pick the most recent record by date. OW returns items sorted
            // oldest-first, so `.last` is normally the freshest — but we also
            // sort defensively in case that ever changes.
            let mostRecent = Self.mostRecentByDate(items)
            completion(mostRecent)
        }.resume()
    }

    /// Inspect each item for a `date` field (`"YYYY-MM-DD"`) via reflection and
    /// return the lexicographically-greatest one. Falls back to `.last` if no
    /// item has a date field. Works for any Decodable struct with a `date: String?`.
    private static func mostRecentByDate<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        let withDates: [(T, String)] = items.compactMap { item in
            let m = Mirror(reflecting: item)
            for child in m.children {
                if child.label == "date", let s = child.value as? String, !s.isEmpty {
                    return (item, s)
                }
                if child.label == "date", let opt = child.value as? String?, let s = opt, !s.isEmpty {
                    return (item, s)
                }
            }
            return nil
        }
        if let best = withDates.max(by: { $0.1 < $1.1 }) {
            return best.0
        }
        return items.last
    }

    // MARK: - Sync orchestration
    /// Fetches recovery/strain/sleep into the published properties.
    /// Optional completion fires on the main queue after all three calls finish
    /// (whether they succeeded or not) — useful for chaining a follow-up like
    /// "now ask Gemini for a summary."
    func performSync(completion: (() -> Void)? = nil) {
        guard isConfigured, isWhoopConnected, !isSyncing else {
            completion?()
            return
        }
        DispatchQueue.main.async {
            self.isSyncing = true
            self.syncError = nil
        }
        let group = DispatchGroup()

        group.enter()
        fetchWhoopRecovery { [weak self] r in
            DispatchQueue.main.async { self?.whoopRecovery = r }
            group.leave()
        }
        group.enter()
        fetchWhoopStrain { [weak self] s in
            DispatchQueue.main.async { self?.whoopStrain = s }
            group.leave()
        }
        group.enter()
        fetchWhoopSleep { [weak self] s in
            DispatchQueue.main.async { self?.whoopSleep = s }
            group.leave()
        }
        group.enter()
        fetchWhoopWorkouts { [weak self] w in
            DispatchQueue.main.async { self?.whoopWorkouts = w }
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            self?.isSyncing = false
            self?.lastSyncDate = Date()
            print("OW sync completed at \(Date())")
            completion?()
        }
    }

    /// POSTs to OW asking it to pull fresh data from Whoop. Fire-and-forget.
    func triggerProviderSync(provider: String = "whoop") {
        guard let uid = userId,
              let req = makeRequest(path: OpenWearablesConfig.Endpoints.triggerSync(provider: provider, userId: uid),
                                    method: "POST") else { return }
        session.dataTask(with: req) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                print("OW triggerSync \(provider): HTTP \(http.statusCode)")
            }
        }.resume()
    }

    private func startPeriodicSync() {
        syncTimer?.invalidate()
        syncTimer = Timer.scheduledTimer(withTimeInterval: Double(OpenWearablesConfig.syncIntervalMinutes * 60), repeats: true) { [weak self] _ in
            self?.performSync()
        }
    }

    // MARK: - Teardown
    func disconnect() {
        apiKey = nil
        userId = nil
        DispatchQueue.main.async {
            self.isWhoopConnected = false
            self.whoopRecovery = nil
            self.whoopStrain = nil
            self.whoopSleep = nil
            self.whoopWorkouts = []
            self.lastSyncDate = nil
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension OpenWearablesManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Wire response models (only what we need to interpret OW responses)
private struct AuthorizeResponse: Decodable {
    let authorizationUrl: String
    let state: String?
}

private struct Connection: Decodable {
    let provider: String
    let status: String?
    let lastSyncedAt: String?
}

private struct PageResponse<T: Decodable>: Decodable {
    let data: [T]
}

// MARK: - Keychain Helper
class KeychainHelper {
    static func save(key: String, data: String) {
        guard let data = data.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        SecItemCopyMatching(query as CFDictionary, &result)
        if let data = result as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
