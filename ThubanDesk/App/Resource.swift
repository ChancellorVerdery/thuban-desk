import Foundation
import Observation
import ThubanDeskCore

/// One remote value with cache-first loading. Views read `value`, `isLoading`, `error`, `fromCache`.
/// Order: cached bytes (instant, `fromCache`) → network when stale or forced → cache updated.
@MainActor
@Observable
final class Resource<Value: Codable & Sendable> {
    let key: String
    let ttl: TimeInterval
    private(set) var value: Value?
    private(set) var loadedAt: Date?
    private(set) var fromCache = false
    private(set) var isLoading = false
    private(set) var error: ThubanError?
    private(set) var hasAttempted = false
    @ObservationIgnored private var inflight: Task<Void, Never>?

    init(key: String, ttl: TimeInterval = 300) {
        self.key = key
        self.ttl = ttl
    }

    var isStale: Bool {
        guard let loadedAt, !fromCache else { return true }
        return Date().timeIntervalSince(loadedAt) > ttl
    }

    var hasValue: Bool { value != nil }

    /// Reads the cache once (no network).
    func prime(cache: DiskCache) async {
        guard value == nil else { return }
        if let entry = await cache.entry(for: key), let decoded = try? GoogleJSON.decoder.decode(Value.self, from: entry.data) {
            value = decoded
            loadedAt = entry.storedAt
            fromCache = true
        }
    }

    /// Loads (cache first, then network when stale or `force`). Concurrent calls share one request.
    func load(cache: DiskCache, force: Bool = false, fetch: @escaping @MainActor () async throws -> Value) async {
        if let inflight { await inflight.value; return }
        await prime(cache: cache)
        guard force || isStale || value == nil else { return }
        let task = Task { @MainActor in
            isLoading = true
            defer { isLoading = false; inflight = nil; hasAttempted = true }
            do {
                let fetched = try await fetch()
                value = fetched
                loadedAt = Date()
                fromCache = false
                error = nil
                if let data = try? GoogleJSON.cacheEncoder.encode(fetched) { await cache.store(data, for: key) }
            } catch let thrown as ThubanError {
                error = thrown
            } catch {
                self.error = .network(error.localizedDescription)
            }
        }
        inflight = task
        await task.value
    }

    /// Replaces the value locally (after a write) and refreshes the cache.
    func replace(_ newValue: Value, cache: DiskCache) {
        value = newValue
        loadedAt = Date()
        fromCache = false
        if let data = try? GoogleJSON.cacheEncoder.encode(newValue) { Task { await cache.store(data, for: key) } }
    }
}
