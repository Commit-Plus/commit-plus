//
//  GitStatusService.swift
//  macgit
//

//
//  macgit (Commit+) - a macOS Git client built with Swift and SwiftUI.
//  Copyright (C) 2026  Thanh Tran <trantienthanh2412@gmail.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.
//
import Foundation

nonisolated struct GitBoundedOutput: Sendable {
    let text: String
    let isTruncated: Bool
}

nonisolated private struct GitProcessResult: Sendable {
    let data: Data
    let isTruncated: Bool
}

nonisolated private final class GitProcessExecution: @unchecked Sendable {
    private let executable: String
    private let arguments: [String]
    private let directory: URL
    private let environment: [String: String]
    private let outputByteLimit: Int?
    private let lock = NSLock()
    private let outputLock = NSLock()
    private let outputGroup = DispatchGroup()

    private var task: Process?
    private var stdout: Pipe?
    private var stderr: Pipe?
    private var stdoutData = Data()
    private var stderrData = Data()
    private var continuation: CheckedContinuation<GitProcessResult, Error>?
    private var didResume = false
    private var wasCancelled = false
    private var isOutputTruncated = false

    init(
        executable: String,
        arguments: [String],
        directory: URL,
        environment: [String: String],
        outputByteLimit: Int? = nil
    ) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
        self.environment = environment
        self.outputByteLimit = outputByteLimit
    }

    func run() async throws -> GitProcessResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(continuation: continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(continuation: CheckedContinuation<GitProcessResult, Error>) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.currentDirectoryURL = directory
        task.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        task.standardOutput = stdout
        task.standardError = stderr

        lock.lock()
        self.task = task
        self.stdout = stdout
        self.stderr = stderr
        self.continuation = continuation
        let cancelledBeforeStart = wasCancelled
        lock.unlock()
        if cancelledBeforeStart { resume(throwing: CancellationError()); return }

        outputGroup.enter()
        outputGroup.enter()
        task.terminationHandler = { [weak self, outputGroup] process in
            outputGroup.notify(queue: .global(qos: .utility)) {
                self?.finish(process: process)
            }
        }

        do {
            try task.run()
            drain(stdout.fileHandleForReading, intoStandardError: false)
            drain(stderr.fileHandleForReading, intoStandardError: true)
            lock.lock()
            let cancelled = wasCancelled
            lock.unlock()
            if cancelled { cancel() }
        } catch {
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForWriting.closeFile()
            outputGroup.leave()
            outputGroup.leave()
            resume(throwing: GitError.gitNotFound)
        }
    }

    private func drain(_ handle: FileHandle, intoStandardError: Bool) {
        let outputGroup = outputGroup
        DispatchQueue.global(qos: .utility).async { [weak self, outputGroup] in
            defer { outputGroup.leave() }
            while true {
                let data = handle.availableData
                guard !data.isEmpty else { return }
                guard let self else { return }
                append(data, intoStandardError: intoStandardError)
            }
        }
    }

    private func append(_ data: Data, intoStandardError: Bool) {
        outputLock.lock()
        defer { outputLock.unlock() }

        guard let outputByteLimit else {
            if intoStandardError {
                stderrData.append(data)
            } else {
                stdoutData.append(data)
            }
            return
        }

        let capturedCount = stdoutData.count + stderrData.count
        let remaining = max(0, outputByteLimit - capturedCount)
        let captured = data.prefix(remaining)
        if intoStandardError {
            stderrData.append(contentsOf: captured)
        } else {
            stdoutData.append(contentsOf: captured)
        }
        if captured.count < data.count {
            isOutputTruncated = true
        }
    }

    private func finish(process: Process) {
        outputLock.lock()
        let outData = stdoutData
        let errData = stderrData
        let isTruncated = isOutputTruncated
        outputLock.unlock()
        let errorOutput = String(decoding: errData, as: UTF8.self)

        lock.lock()
        let cancelled = wasCancelled
        lock.unlock()
        if cancelled {
            resume(throwing: CancellationError())
        } else if process.terminationStatus != 0 {
            let output = String(decoding: outData, as: UTF8.self)
            // Git can write progress to stderr and the actual failure (such as merge conflicts) to stdout.
            let message = [errorOutput, output]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            resume(throwing: GitError.commandFailed(message))
        } else {
            resume(returning: GitProcessResult(data: outData, isTruncated: isTruncated))
        }
    }

    private func cancel() {
        lock.lock()
        wasCancelled = true
        let process = task
        lock.unlock()
        guard let process, process.isRunning else { return }
        Self.terminateChildren(of: process.processIdentifier)
        process.terminate()
        // Completion waits for process exit and pipe draining before callers release credentials.
    }

    private static func terminateChildren(of pid: Int32) {
        var children = [Int32](repeating: 0, count: 4096)
        let capacity = Int32(children.count * MemoryLayout<Int32>.size)
        let byteCount = children.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, capacity) }
        guard byteCount > 0 else { return }
        for child in children.prefix(Int(byteCount) / MemoryLayout<Int32>.size) where child > 0 && child != pid {
            terminateChildren(of: child)
            kill(child, SIGTERM)
        }
    }

    private func resume(returning result: GitProcessResult) {
        complete { continuation in
            continuation.resume(returning: result)
        }
    }

    private func resume(throwing error: Error) {
        complete { continuation in
            continuation.resume(throwing: error)
        }
    }

    private func complete(_ resume: (CheckedContinuation<GitProcessResult, Error>) -> Void) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        self.task = nil
        self.stdout = nil
        self.stderr = nil
        lock.unlock()

        resume(continuation)
    }
}

actor GitStatusService {
    static let shared = GitStatusService()

    private let runner: (any GitCommandRunning)?
    let runtimeManager: GitRuntimeManager
    let lfsRuntime: GitLFSRuntime
    let branchListCache = BranchListCache()
    var lfsMutations = Set<String>()
    private var gitCorePaths: [String: String] = [:]

    init(
        runner: (any GitCommandRunning)? = nil,
        runtimeManager: GitRuntimeManager = .shared,
        lfsRuntime: GitLFSRuntime = .shared
    ) {
        self.runner = runner
        self.runtimeManager = runtimeManager
        self.lfsRuntime = lfsRuntime
    }

    func gitExecutable() async throws -> String {
        try await runtimeManager.executableURL().path
    }

    func gitExecutionContext(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> (executable: String, environment: [String: String]) {
        let executableURL = try await runtimeManager.executableURL()
        var resolvedEnvironment = await runtimeManager.environment(
            for: executableURL,
            inheriting: environment
        )
        resolvedEnvironment["PATH"] = executableURL.deletingLastPathComponent().path + ":" + (resolvedEnvironment["PATH"] ?? "/usr/bin:/bin")
        if resolvedEnvironment["GIT_EXEC_PATH"] == nil {
            if let cached = gitCorePaths[executableURL.path] {
                resolvedEnvironment["GIT_EXEC_PATH"] = cached
            } else {
                let result = try await GitProcessExecution(executable: executableURL.path, arguments: ["--exec-path"],
                    directory: FileManager.default.temporaryDirectory, environment: resolvedEnvironment, outputByteLimit: 16_384).run()
                let path = String(decoding: result.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                gitCorePaths[executableURL.path] = path
                resolvedEnvironment["GIT_EXEC_PATH"] = path
            }
        }
        return (executableURL.path, try await lfsRuntime.environment(inheriting: resolvedEnvironment))
    }

    func runGit(arguments: [String], in directory: URL) async throws -> String {
        if let runner {
            let startedAt = Date()
            do {
                let output = try await runner.runGit(arguments: arguments, in: directory)
                await GitCommandLogStore.shared.record(
                    arguments: arguments,
                    directory: directory,
                    duration: Date().timeIntervalSince(startedAt),
                    error: nil
                )
                return output
            } catch {
                await GitCommandLogStore.shared.record(
                    arguments: arguments,
                    directory: directory,
                    duration: Date().timeIntervalSince(startedAt),
                    error: error
                )
                throw error
            }
        }
        let data = try await runGitRaw(arguments: arguments, in: directory)
        return String(decoding: data, as: UTF8.self)
    }

    func runGit(arguments: [String], in directory: URL, environment: [String: String]) async throws -> String {
        if let runner {
            let startedAt = Date()
            do {
                let output = try await runner.runGit(
                    arguments: arguments,
                    in: directory,
                    environment: environment
                )
                await GitCommandLogStore.shared.record(
                    arguments: arguments,
                    directory: directory,
                    duration: Date().timeIntervalSince(startedAt),
                    error: nil
                )
                return output
            } catch {
                await GitCommandLogStore.shared.record(
                    arguments: arguments,
                    directory: directory,
                    duration: Date().timeIntervalSince(startedAt),
                    error: error
                )
                throw error
            }
        }
        let data = try await runGitRaw(arguments: arguments, in: directory, environment: environment)
        return String(decoding: data, as: UTF8.self)
    }

    func runGitBounded(
        arguments: [String],
        in directory: URL,
        environment: [String: String],
        outputByteLimit: Int
    ) async throws -> GitBoundedOutput {
        let limit = max(1, outputByteLimit)
        if let runner {
            let startedAt = Date.now
            do {
                let output = try await runner.runGit(
                    arguments: arguments,
                    in: directory,
                    environment: environment
                )
                await GitCommandLogStore.shared.record(
                    arguments: arguments,
                    directory: directory,
                    duration: Date.now.timeIntervalSince(startedAt),
                    error: nil
                )
                let bytes = Data(output.utf8)
                return GitBoundedOutput(
                    text: String(decoding: bytes.prefix(limit), as: UTF8.self),
                    isTruncated: bytes.count > limit
                )
            } catch {
                await GitCommandLogStore.shared.record(
                    arguments: arguments,
                    directory: directory,
                    duration: Date.now.timeIntervalSince(startedAt),
                    error: error
                )
                throw error
            }
        }

        let startedAt = Date.now
        do {
            let context = try await gitExecutionContext(environment: environment)
            let execution = GitProcessExecution(
                executable: context.executable,
                arguments: arguments,
                directory: directory,
                environment: context.environment,
                outputByteLimit: limit
            )
            let result = try await execution.run()
            await GitCommandLogStore.shared.record(
                arguments: arguments,
                directory: directory,
                duration: Date.now.timeIntervalSince(startedAt),
                error: nil
            )
            return GitBoundedOutput(
                text: String(decoding: result.data, as: UTF8.self),
                isTruncated: result.isTruncated
            )
        } catch {
            await GitCommandLogStore.shared.record(
                arguments: arguments,
                directory: directory,
                duration: Date.now.timeIntervalSince(startedAt),
                error: error
            )
            throw error
        }
    }

    func runGitRaw(arguments: [String], in directory: URL) async throws -> Data {
        try await runGitRaw(
            arguments: arguments,
            in: directory,
            environment: ProcessInfo.processInfo.environment
        )
    }

    func runGitRaw(arguments: [String], in directory: URL, environment: [String: String], outputByteLimit: Int? = nil) async throws -> Data {
        let startedAt = Date()
        do {
            let context = try await gitExecutionContext(environment: environment)
            let result = try await GitProcessExecution(
                executable: context.executable,
                arguments: arguments,
                directory: directory,
                environment: context.environment,
                outputByteLimit: outputByteLimit
            ).run()
            guard !result.isTruncated else {
                throw GitError.commandFailed("Git object exceeds the preview limit.")
            }
            await GitCommandLogStore.shared.record(
                arguments: arguments,
                directory: directory,
                duration: Date().timeIntervalSince(startedAt),
                error: nil
            )
            return result.data
        } catch {
            await GitCommandLogStore.shared.record(
                arguments: arguments,
                directory: directory,
                duration: Date().timeIntervalSince(startedAt),
                error: error
            )
            throw error
        }
    }

    func clearSessionCaches() async {
        await branchListCache.removeAll()
    }

    func runProcessRaw(executableURL: URL, arguments: [String], in directory: URL) async throws -> Data {
        try await runProcessRaw(
            executableURL: executableURL,
            arguments: arguments,
            in: directory,
            environment: ProcessInfo.processInfo.environment
        )
    }

    func runProcessRaw(
        executableURL: URL,
        arguments: [String],
        in directory: URL,
        environment: [String: String],
        outputByteLimit: Int? = nil
    ) async throws -> Data {
        let result = try await GitProcessExecution(
            executable: executableURL.path,
            arguments: arguments,
            directory: directory,
            environment: environment,
            outputByteLimit: outputByteLimit
        ).run()
        guard !result.isTruncated else { throw GitError.commandFailed("Command output exceeded the safety limit.") }
        return result.data
    }

    struct PushOptions {
        var remote: String = "origin"
        var branches: [String] = []
        var branchMappings: [String: String] = [:] // local branch -> remote branch name
        var tags: [String] = []
        var forceTags: Bool = false
        var pushTags: Bool = false
    }

    struct PullOptions {
        var commitMerged: Bool = true
        var includeMessages: Bool = true
        var noFastForward: Bool = false
        var rebaseInstead: Bool = false
    }

    struct MergeOptions {
        var noFastForward: Bool = false
        var squash: Bool = false
        var message: String = ""
    }

    struct StashOptions {
        var message: String = ""
        var keepIndex: Bool = false
        var paths: [String] = []
        var includeUntracked: Bool = false
    }

    struct FetchOptions {
        var fetchAllRemotes: Bool = true
        var prune: Bool = false
        var fetchTags: Bool = false
    }

    enum ConflictResolution {
        case ours, theirs
    }
}
