import Foundation
import Synchronization
import Darwin

nonisolated enum ToolRunner {
    enum Failure: Error { case cancelled, failed(Int32), outputLimit }

    static func run(_ path: String, _ arguments: [String], timeout: Duration = .seconds(30)) async throws -> String {
        let tool = RunningTool(path: path, arguments: arguments)
        let done = OneShot<Result<String, any Error>>()
        Task.detached {
            do { done.resolve(.success(try tool.execute())) }
            catch { done.resolve(.failure(error)) }
        }
        defer { tool.cancel() }
        return try await done.wait(timeout: timeout).get()
    }

    private final class RunningTool: Sendable {
        private struct State {
            let process: Process
            var cancelled = false
        }
        private let state: Mutex<State>
        private let pipe = Pipe()

        init(path: String, arguments: [String]) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = pipe
            process.standardError = pipe
            state = Mutex(State(process: process))
        }

        func execute() throws -> String {
            try state.withLock { s in
                guard !s.cancelled else { throw Failure.cancelled }
                try s.process.run()
            }
            var output = Data()
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                guard output.count + chunk.count <= 1_048_576 else { throw Failure.outputLimit }
                output.append(chunk)
            }
            let exit = state.withLock { $0.process }
            exit.waitUntilExit()
            guard exit.terminationStatus == 0 else { throw Failure.failed(exit.terminationStatus) }
            return String(decoding: output, as: UTF8.self)
        }

        func cancel() {
            state.withLock { s in
                s.cancelled = true
                if s.process.isRunning { s.process.terminate() }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) { [self] in
                state.withLock { s in
                    if s.process.isRunning { kill(s.process.processIdentifier, SIGKILL) }
                }
            }
        }
    }
}
