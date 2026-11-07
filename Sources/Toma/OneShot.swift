import Foundation
import Synchronization

nonisolated final class OneShot<Value: Sendable>: Sendable {
    enum WaitFailure: Error { case timedOut, cancelled }
    private struct State {
        var value: Value?
        var waiters: [CheckedContinuation<Value, Never>] = []
        var active: Set<UUID> = []
        var timed: [UUID: CheckedContinuation<Value, any Error>] = [:]
        var pending: [UUID: WaitFailure] = [:]
    }
    private let state = Mutex(State())

    func resolve(_ value: Value) {
        let callbacks = state.withLock { s -> ([CheckedContinuation<Value, Never>], [CheckedContinuation<Value, any Error>]) in
            guard s.value == nil else { return ([], []) }
            s.value = value
            let callbacks = (s.waiters, Array(s.timed.values))
            s.active.subtract(s.timed.keys)
            s.waiters = []
            s.timed = [:]
            return callbacks
        }
        for waiter in callbacks.0 { waiter.resume(returning: value) }
        for waiter in callbacks.1 { waiter.resume(returning: value) }
    }

    var value: Value {
        get async {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { s -> Value? in
                    if let value = s.value { return value }
                    s.waiters.append(continuation)
                    return nil
                }
                if let ready { continuation.resume(returning: ready) }
            }
        }
    }

    func wait(timeout: Duration) async throws -> Value {
        let id = UUID()
        _ = state.withLock { $0.active.insert(id) }
        let timer = Task {
            do { try await Task.sleep(for: timeout) } catch { return }
            finish(id, failure: .timedOut)
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let ready = state.withLock { s -> Result<Value, WaitFailure>? in
                    if let failure = s.pending.removeValue(forKey: id) { return .failure(failure) }
                    if let value = s.value { s.active.remove(id); return .success(value) }
                    s.timed[id] = continuation
                    return nil
                }
                if let ready { continuation.resume(with: ready.mapError { $0 as any Error }) }
            }
        } onCancel: {
            self.finish(id, failure: .cancelled)
        }
    }

    private func finish(_ id: UUID, failure: WaitFailure) {
        let waiter = state.withLock { s -> CheckedContinuation<Value, any Error>? in
            guard s.active.remove(id) != nil else { return nil }
            if let waiter = s.timed.removeValue(forKey: id) { return waiter }
            s.pending[id] = failure
            return nil
        }
        waiter?.resume(throwing: failure)
    }
}
