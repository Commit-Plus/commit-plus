// SPDX-License-Identifier: AGPL-3.0-or-later

import Darwin
import Foundation

private struct CustomActionProcessResult: Sendable {
    let exitCode: Int32?
    let standardOutput: Data
    let standardError: Data
    let isStandardOutputTruncated: Bool
    let isStandardErrorTruncated: Bool
    let wasCancelled: Bool
}

private final class CustomActionProcessExecution: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let directoryURL: URL
    private let outputByteLimit: Int
    private let lock = NSLock()
    private let outputLock = NSLock()
    private let outputGroup = DispatchGroup()

    private var process: Process?
    private var continuation: CheckedContinuation<CustomActionProcessResult, Never>?
    private var didResume = false
    private var wasCancelled = false
    private var stdoutData = Data()
    private var stderrData = Data()
    private var stdoutTruncated = false
    private var stderrTruncated = false

    init(executableURL: URL, arguments: [String], directoryURL: URL, outputByteLimit: Int) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.directoryURL = directoryURL
        self.outputByteLimit = outputByteLimit
    }

    func run() async -> CustomActionProcessResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                start(continuation)
            }
        } onCancel: {
            cancel()
        }
    }

    private func start(_ continuation: CheckedContinuation<CustomActionProcessResult, Never>) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = directoryURL
        process.environment = ProcessInfo.processInfo.environment
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        lock.lock()
        self.process = process
        self.continuation = continuation
        let cancelledBeforeStart = wasCancelled
        lock.unlock()
        guard !cancelledBeforeStart else {
            finishWithoutProcess()
            return
        }

        outputGroup.enter()
        outputGroup.enter()
        process.terminationHandler = { [weak self, outputGroup] process in
            outputGroup.notify(queue: .global(qos: .utility)) {
                self?.finish(process)
            }
        }

        do {
            try process.run()
            drain(stdout.fileHandleForReading, isStandardError: false)
            drain(stderr.fileHandleForReading, isStandardError: true)
            lock.lock()
            let cancelled = wasCancelled
            lock.unlock()
            if cancelled { cancel() }
        } catch {
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForWriting.closeFile()
            outputGroup.leave()
            outputGroup.leave()
            finishWithoutProcess(error: error.localizedDescription)
        }
    }

    private func drain(_ handle: FileHandle, isStandardError: Bool) {
        let outputGroup = outputGroup
        DispatchQueue.global(qos: .utility).async { [weak self, outputGroup] in
            defer { outputGroup.leave() }
            while true {
                let data = handle.availableData
                guard !data.isEmpty, let self else { return }
                append(data, isStandardError: isStandardError)
            }
        }
    }

    private func append(_ data: Data, isStandardError: Bool) {
        outputLock.lock()
        defer { outputLock.unlock() }
        if isStandardError {
            let remaining = max(0, outputByteLimit - stderrData.count)
            stderrData.append(contentsOf: data.prefix(remaining))
            stderrTruncated = stderrTruncated || data.count > remaining
        } else {
            let remaining = max(0, outputByteLimit - stdoutData.count)
            stdoutData.append(contentsOf: data.prefix(remaining))
            stdoutTruncated = stdoutTruncated || data.count > remaining
        }
    }

    private func finish(_ process: Process) {
        outputLock.lock()
        let stdout = stdoutData
        let stderr = stderrData
        let stdoutTruncated = stdoutTruncated
        let stderrTruncated = stderrTruncated
        outputLock.unlock()
        lock.lock()
        let cancelled = wasCancelled
        lock.unlock()
        resume(CustomActionProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: stdout,
            standardError: stderr,
            isStandardOutputTruncated: stdoutTruncated,
            isStandardErrorTruncated: stderrTruncated,
            wasCancelled: cancelled
        ))
    }

    private func finishWithoutProcess(error: String? = nil) {
        resume(CustomActionProcessResult(
            exitCode: nil,
            standardOutput: Data(),
            standardError: Data((error ?? "Action cancelled before launch.").utf8),
            isStandardOutputTruncated: false,
            isStandardErrorTruncated: false,
            wasCancelled: wasCancelled
        ))
    }

    private func cancel() {
        lock.lock()
        wasCancelled = true
        let process = process
        lock.unlock()
        guard let process, process.isRunning else { return }
        Self.terminateChildren(of: process.processIdentifier)
        process.terminate()
    }

    private static func terminateChildren(of pid: Int32) {
        var children = [Int32](repeating: 0, count: 4096)
        let capacity = Int32(children.count * MemoryLayout<Int32>.size)
        let count = children.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, capacity) }
        guard count > 0 else { return }
        for child in children.prefix(min(Int(count), children.count)) where child > 0 && child != pid {
            terminateChildren(of: child)
            kill(child, SIGTERM)
        }
    }

    private func resume(_ result: CustomActionProcessResult) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }
        didResume = true
        self.continuation = nil
        self.process = nil
        lock.unlock()
        continuation.resume(returning: result)
    }
}

actor CustomActionExecutor {
    static let outputByteLimit = 1_048_576

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func execute(
        action: CustomActionDefinition,
        context: CustomActionInvocationContext
    ) async -> CustomActionExecutionResult {
        let startedAt = Date.now
        do {
            try CustomActionValidator.validate(action, fileManager: fileManager)
            let command = try prepareCommand(action: action, context: context)
            let processResult = await CustomActionProcessExecution(
                executableURL: command.executableURL,
                arguments: command.arguments,
                directoryURL: context.repositoryURL,
                outputByteLimit: Self.outputByteLimit
            ).run()
            let status: CustomActionExecutionStatus
            if processResult.wasCancelled || Task.isCancelled {
                status = .cancelled
            } else if processResult.exitCode == 0 {
                status = .succeeded
            } else {
                status = .failed
            }
            return result(
                action: action,
                context: context,
                status: status,
                processResult: processResult,
                startedAt: startedAt
            )
        } catch {
            return CustomActionExecutionResult(
                action: action,
                context: context,
                status: Task.isCancelled ? .cancelled : .failed,
                exitCode: nil,
                standardOutput: "",
                standardError: error.localizedDescription,
                isStandardOutputTruncated: false,
                isStandardErrorTruncated: false,
                duration: Date.now.timeIntervalSince(startedAt)
            )
        }
    }

    private func prepareCommand(
        action: CustomActionDefinition,
        context: CustomActionInvocationContext
    ) throws -> (executableURL: URL, arguments: [String]) {
        let expandedArguments = CustomActionArgumentExpander.expand(action.arguments, context: context)
        switch action.sourceKind {
        case .executable:
            return (URL(fileURLWithPath: action.executablePath), expandedArguments)
        case .localScript:
            guard let language = action.scriptLanguage else {
                throw CustomActionValidationError.missingScriptLanguage
            }
            return interpreterCommand(
                language: language,
                scriptURL: URL(fileURLWithPath: action.executablePath),
                arguments: expandedArguments
            )
        case .syncedScript:
            guard let language = action.scriptLanguage,
                  let source = action.scriptSource else {
                throw CustomActionValidationError.missingScriptSource
            }
            let scriptURL = try materialize(
                source: source,
                fileName: action.sourceFileName,
                action: action
            )
            return interpreterCommand(
                language: language,
                scriptURL: scriptURL,
                arguments: expandedArguments
            )
        }
    }

    private func interpreterCommand(
        language: CustomActionScriptLanguage,
        scriptURL: URL,
        arguments: [String]
    ) -> (executableURL: URL, arguments: [String]) {
        switch language {
        case .sh:
            (URL(fileURLWithPath: "/bin/sh"), [scriptURL.path] + arguments)
        case .bash:
            (URL(fileURLWithPath: "/bin/bash"), [scriptURL.path] + arguments)
        case .zsh:
            (URL(fileURLWithPath: "/bin/zsh"), [scriptURL.path] + arguments)
        case .python:
            (URL(fileURLWithPath: "/usr/bin/env"), ["python3", scriptURL.path] + arguments)
        }
    }

    private func materialize(
        source: String,
        fileName: String?,
        action: CustomActionDefinition
    ) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("Commit+", isDirectory: true)
            .appendingPathComponent("CustomActions", isDirectory: true)
            .appendingPathComponent(action.id.uuidString, isDirectory: true)
            .appendingPathComponent(action.trustFingerprint, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = URL(fileURLWithPath: fileName ?? "script").lastPathComponent
        let scriptURL = directory.appendingPathComponent(safeName.isEmpty ? "script" : safeName)
        try Data(source.utf8).write(to: scriptURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scriptURL.path)
        return scriptURL
    }

    private func result(
        action: CustomActionDefinition,
        context: CustomActionInvocationContext,
        status: CustomActionExecutionStatus,
        processResult: CustomActionProcessResult,
        startedAt: Date
    ) -> CustomActionExecutionResult {
        CustomActionExecutionResult(
            action: action,
            context: context,
            status: status,
            exitCode: processResult.exitCode,
            standardOutput: String(decoding: processResult.standardOutput, as: UTF8.self),
            standardError: String(decoding: processResult.standardError, as: UTF8.self),
            isStandardOutputTruncated: processResult.isStandardOutputTruncated,
            isStandardErrorTruncated: processResult.isStandardErrorTruncated,
            duration: Date.now.timeIntervalSince(startedAt)
        )
    }
}
