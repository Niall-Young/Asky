import Foundation
import os

public enum ScopeKind: String, Sendable {
    case app, panel, search, task, disk
}

/// Owns cancellable work and release handlers for a bounded lifetime.
/// Ending a scope cancels its tasks and runs release handlers exactly once.
public final class ResourceScope: Sendable {
    public let owner: String
    public let kind: ScopeKind
    private struct State {
        var ended = false
        var tasks: [UUID: Task<Void, Never>] = [:]
        var releases: [@Sendable () -> Void] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    public init(owner: String, kind: ScopeKind) {
        self.owner = owner
        self.kind = kind
    }

    public var isEnded: Bool { state.withLock { $0.ended } }

    public var activeTaskCount: Int { state.withLock { $0.tasks.values.filter { !$0.isCancelled }.count } }

    /// Starts work owned by the scope. If already ended the work is cancelled immediately.
    @discardableResult
    public func run(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        state.withLock { s in
            guard !s.ended else {
                let task = Task<Void, Never> {}
                task.cancel()
                return task
            }
            let id = UUID()
            let task = Task { [weak self] in
                await operation()
                self?.state.withLock { $0.tasks[id] = nil }
            }
            s.tasks[id] = task
            return task
        }
    }

    public func onEnd(_ release: @escaping @Sendable () -> Void) {
        let runNow = state.withLock { s -> Bool in
            if s.ended { return true }
            s.releases.append(release)
            return false
        }
        if runNow { release() }
    }

    public func end() {
        let (tasks, releases) = state.withLock { s -> ([Task<Void, Never>], [@Sendable () -> Void]) in
            guard !s.ended else { return ([], []) }
            s.ended = true
            defer { s.tasks = [:]; s.releases = [] }
            return (Array(s.tasks.values), s.releases)
        }
        tasks.forEach { $0.cancel() }
        releases.forEach { $0() }
    }

    deinit { end() }
}
