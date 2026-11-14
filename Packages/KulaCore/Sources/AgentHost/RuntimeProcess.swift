import Foundation

/// Runtime lifecycle adapter; NativeRuntime uses an in-memory channel and a negative local identity.
public protocol RuntimeProcess: Sendable {
    var pid: Int32 { get }
    /// Event frames; finishes when the runtime stops.
    var output: AsyncStream<Data> { get }
    func write(_ data: Data) throws
    /// Closes the command channel.
    func closeInput()
    /// Cancels runtime work. Native runtimes use cooperative task cancellation.
    func terminate(force: Bool)
    /// Waits for runtime teardown and returns its status.
    func waitForExit() async -> Int32
}
