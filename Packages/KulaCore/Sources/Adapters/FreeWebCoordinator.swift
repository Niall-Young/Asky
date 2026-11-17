import Foundation
import Contracts

/// Shared only by web adapters: bounded, expiring memory; no disk cache or background requests.
actor FreeWebCoordinator {
    static let shared = FreeWebCoordinator()
    private struct Entry {
        let value: JSONValue
        let expires: Date
        let bytes: Int
        let inserted: Date
    }
    private struct Waiter {
        let continuation: CheckedContinuation<JSONValue, any Error>
        let shared: Bool
    }
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: Waiter]
    }
    private struct Cooldown {
        let until: Date
        let failure: FreeWebFailure
    }
    private let ttl: TimeInterval
    private let byteLimit: Int
    private let entryLimit: Int
    private let now: @Sendable () -> Date
    private var cache: [String: Entry] = [:]
    private var flights: [String: Flight] = [:]
    private var cooldowns: [FreeWebProvider: Cooldown] = [:]
    private var cleanup: Task<Void, Never>?
    private var backupCursor = 0

    init(ttl: TimeInterval = 600, byteLimit: Int = 2_097_152, entryLimit: Int = 32,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl; self.byteLimit = byteLimit; self.entryLimit = entryLimit; self.now = now
    }

    func providers() -> [FreeWebProvider] {
        let backups: [FreeWebProvider] = [.exa, .keenable]
        let order = Array(backups[backupCursor...] + backups[..<backupCursor])
        backupCursor = (backupCursor + 1) % backups.count
        return [.parallel] + order
    }

    func skip(_ provider: FreeWebProvider) -> JSONValue? {
        guard let cooldown = cooldowns[provider] else { return nil }
        let remaining = cooldown.until.timeIntervalSince(now())
        guard remaining > 0 else { cooldowns.removeValue(forKey: provider); return nil }
        return ["provider": .string(provider.rawValue), "status": .string(cooldown.failure.status),
                "skipped": true, "stage": "cooldown", "retryAfterSeconds": .number(ceil(remaining)),
                "error": .string(cooldown.failure.message)]
    }

    func record(_ error: Error, provider: FreeWebProvider) {
        guard let failure = error as? FreeWebFailure, failure.stage != "page" else { return }
        // A crawler rejecting one URL does not make the provider's search or other pages
        // unavailable. Only service/network failures and rate limits cool down the provider.
        let pageFailure = failure.httpStatus == 422 || failure.message.range(
            of: "CRAWL_NOT_FOUND|CRAWL_LIVECRAWL_TIMEOUT|content_not_extracted|No content for requested URL",
            options: [.regularExpression, .caseInsensitive]) != nil
        if failure.status != "rate_limited" && pageFailure { return }
        // Preserve Retry-After; do not create a new identity to bypass a provider's limit.
        let delay = failure.retryAfter ?? (failure.status == "rate_limited" ? 60 :
            [401, 402, 403].contains(failure.httpStatus ?? 0) ? 600 : 15)
        let until = now().addingTimeInterval(max(1, delay))
        if until > (cooldowns[provider]?.until ?? .distantPast) {
            cooldowns[provider] = Cooldown(until: until, failure: failure)
        }
    }

    func run(key: String, operation: @escaping @Sendable () async throws -> JSONValue) async throws -> JSONValue {
        try Task.checkCancellation()
        purge()
        if let entry = cache[key] { return reused(entry.value, cached: true) }
        let waiterID = UUID()
        let result: JSONValue = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, any Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                if flights[key] != nil {
                    flights[key]?.waiters[waiterID] = Waiter(continuation: continuation, shared: true)
                    return
                }
                let flightID = UUID()
                let task = Task {
                    let result: Result<JSONValue, any Error>
                    do { result = .success(try await operation()) }
                    catch { result = .failure(error) }
                    self.finish(key: key, id: flightID, result: result)
                }
                flights[key] = Flight(id: flightID, task: task,
                    waiters: [waiterID: Waiter(continuation: continuation, shared: false)])
            }
        } onCancel: {
            Task { await self.cancel(key: key, waiter: waiterID) }
        }
        try Task.checkCancellation()
        return result
    }

    private func cancel(key: String, waiter: UUID) {
        guard let pending = flights[key]?.waiters.removeValue(forKey: waiter) else { return }
        pending.continuation.resume(throwing: CancellationError())
        if flights[key]?.waiters.isEmpty == true {
            flights.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func finish(key: String, id: UUID, result: Result<JSONValue, any Error>) {
        guard flights[key]?.id == id, let flight = flights.removeValue(forKey: key) else { return }
        if case .success(let value) = result { insert(value, key: key) }
        for waiter in flight.waiters.values {
            waiter.continuation.resume(with: result.map { waiter.shared ? reused($0, cached: false) : $0 })
        }
    }

    private func reused(_ value: JSONValue, cached: Bool) -> JSONValue {
        var object = value.objectValue ?? [:]
        object["cached"] = .bool(cached)
        object["coalesced"] = .bool(!cached)
        object["sourceAttempts"] = object["attempts"]
        object["attempts"] = [] // Historical attempts must not be counted as fresh provider calls.
        return .object(object)
    }

    private func insert(_ value: JSONValue, key: String) {
        let successful = value["status"]?.stringValue == "read" ||
            (["matched", "partial"].contains(value["status"]?.stringValue ?? "") &&
             value["results"]?.arrayValue?.isEmpty == false)
        guard successful else { return }
        let bytes = value.canonicalData().count + key.utf8.count
        guard bytes <= byteLimit, entryLimit > 0 else { return }
        purge()
        cache.removeValue(forKey: key)
        while cache.count >= entryLimit || cache.values.reduce(0, { $0 + $1.bytes }) + bytes > byteLimit {
            guard let oldest = cache.min(by: { $0.value.inserted < $1.value.inserted })?.key else { break }
            cache.removeValue(forKey: oldest)
        }
        cache[key] = Entry(value: value, expires: now().addingTimeInterval(ttl), bytes: bytes, inserted: now())
        scheduleCleanup()
    }

    private func purge() {
        let date = now()
        cache = cache.filter { $0.value.expires > date }
        cooldowns = cooldowns.filter { $0.value.until > date }
    }

    private func scheduleCleanup() {
        cleanup?.cancel()
        guard let expiry = cache.values.map(\.expires).min() else { cleanup = nil; return }
        let delay = max(0.01, expiry.timeIntervalSince(now()))
        cleanup = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await self?.expire()
        }
    }

    private func expire() { purge(); scheduleCleanup() }
}
