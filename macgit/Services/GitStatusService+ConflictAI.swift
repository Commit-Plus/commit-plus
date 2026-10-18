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

import CryptoKit
import Foundation

nonisolated protocol ConflictAIFileServicing: Sendable {
    func loadConflictAIFile(
        _ file: StatusFile,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> ConflictAILoadedFile

    func conflictAIFingerprint(for file: StatusFile, in repositoryURL: URL) async throws -> String

    func applyAIConflictResolution(
        file: StatusFile,
        document: ConflictResolutionDocument,
        expectedFingerprint: String,
        originalWorkingTreeText: String,
        in repositoryURL: URL
    ) async throws
}

extension GitStatusService: ConflictAIFileServicing {
    func loadConflictAIFile(
        _ file: StatusFile,
        in repositoryURL: URL,
        characterBudget: Int
    ) async throws -> ConflictAILoadedFile {
        guard !file.isBinary else {
            throw ConflictAIResolutionError.unsupportedFile(
                "\(file.path) is binary and must be resolved manually."
            )
        }

        let fileURL = repositoryURL.appending(path: file.path)
        let workingData = try Data(contentsOf: fileURL)
        let currentData = try await conflictStageFile(at: file.path, stage: 2, in: repositoryURL)
        let incomingData = try await conflictStageFile(at: file.path, stage: 3, in: repositoryURL)
        let baseData = try? await conflictStageFile(at: file.path, stage: 1, in: repositoryURL)

        let workingText = try decodeConflictText(workingData, path: file.path)
        let currentText = try decodeConflictText(currentData, path: file.path)
        let incomingText = try decodeConflictText(incomingData, path: file.path)
        let baseText = try baseData.map { try decodeConflictText($0, path: file.path) }
        let document = try ConflictResolutionDocument.parse(
            workingText,
            currentContent: currentText,
            incomingContent: incomingText
        )
        guard document.conflictCount > 0 else {
            throw ConflictAIResolutionError.unsupportedFile(
                "\(file.path) does not contain text conflict markers."
            )
        }

        let fingerprint = conflictAIFingerprint(
            path: file.path,
            workingData: workingData,
            baseData: baseData,
            currentData: currentData,
            incomingData: incomingData
        )
        let branchName = await currentBranch(in: repositoryURL)
        let sections = conflictAISectionSnapshots(from: document)
        let initialSnapshot = ConflictAIFileSnapshot(
            repositoryName: repositoryURL.lastPathComponent,
            branchName: branchName,
            filePath: file.path,
            fingerprint: fingerprint,
            baseContent: baseText,
            currentContent: currentText,
            incomingContent: incomingText,
            sections: sections,
            isTruncated: false
        )
        let promptContext = try ConflictAIPrompt.context(
            for: initialSnapshot,
            characterBudget: characterBudget
        )
        let snapshot = ConflictAIFileSnapshot(
            repositoryName: initialSnapshot.repositoryName,
            branchName: initialSnapshot.branchName,
            filePath: initialSnapshot.filePath,
            fingerprint: initialSnapshot.fingerprint,
            baseContent: initialSnapshot.baseContent,
            currentContent: initialSnapshot.currentContent,
            incomingContent: initialSnapshot.incomingContent,
            sections: initialSnapshot.sections,
            isTruncated: promptContext.contains("[Additional file context omitted]")
        )
        return ConflictAILoadedFile(
            file: file,
            document: document,
            snapshot: snapshot,
            originalWorkingTreeText: workingText
        )
    }

    func conflictAIFingerprint(for file: StatusFile, in repositoryURL: URL) async throws -> String {
        let fileURL = repositoryURL.appending(path: file.path)
        let workingData = try Data(contentsOf: fileURL)
        let currentData = try await conflictStageFile(at: file.path, stage: 2, in: repositoryURL)
        let incomingData = try await conflictStageFile(at: file.path, stage: 3, in: repositoryURL)
        let baseData = try? await conflictStageFile(at: file.path, stage: 1, in: repositoryURL)
        return conflictAIFingerprint(
            path: file.path,
            workingData: workingData,
            baseData: baseData,
            currentData: currentData,
            incomingData: incomingData
        )
    }

    func applyAIConflictResolution(
        file: StatusFile,
        document: ConflictResolutionDocument,
        expectedFingerprint: String,
        originalWorkingTreeText: String,
        in repositoryURL: URL
    ) async throws {
        let currentFingerprint = try await conflictAIFingerprint(for: file, in: repositoryURL)
        guard currentFingerprint == expectedFingerprint else {
            throw ConflictAIResolutionError.staleFile(
                "\(file.path) changed while AI was resolving it. Run Resolve All with AI again."
            )
        }
        guard document.sections.allSatisfy({ !$0.isConflict || $0.isResolved }) else {
            throw ConflictAIResolutionError.incompletePlan(
                "AI did not resolve every conflict in \(file.path)."
            )
        }
        let resolvedText = document.resolvedText
        guard !containsConflictMarkers(resolvedText) else {
            throw ConflictAIResolutionError.unsafeReplacement(
                "AI left conflict markers in \(file.path)."
            )
        }

        let fileURL = repositoryURL.appending(path: file.path)
        try resolvedText.write(to: fileURL, atomically: true, encoding: .utf8)
        do {
            _ = try await runGit(arguments: ["diff", "--check", "--", file.path], in: repositoryURL)
            _ = try await runGit(arguments: ["add", "--", file.path], in: repositoryURL)
        } catch {
            try? originalWorkingTreeText.write(to: fileURL, atomically: true, encoding: .utf8)
            throw error
        }
    }

    private func decodeConflictText(_ data: Data, path: String) throws -> String {
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw ConflictAIResolutionError.unsupportedFile(
                "\(path) is not UTF-8 text and must be resolved manually."
            )
        }
        return text
    }

    private func conflictAISectionSnapshots(
        from document: ConflictResolutionDocument
    ) -> [ConflictAISectionSnapshot] {
        document.sections.indices.compactMap { index in
            let section = document.sections[index]
            guard section.isConflict else { return nil }
            let contextBefore = index > document.sections.startIndex
                ? String(document.sections[index - 1].contextText.suffix(800))
                : ""
            let contextAfter = index < document.sections.index(before: document.sections.endIndex)
                ? String(document.sections[index + 1].contextText.prefix(800))
                : ""
            return ConflictAISectionSnapshot(
                sectionIndex: index,
                contextBefore: contextBefore,
                currentText: section.currentText,
                incomingText: section.incomingText,
                contextAfter: contextAfter
            )
        }
    }

    private func conflictAIFingerprint(
        path: String,
        workingData: Data,
        baseData: Data?,
        currentData: Data,
        incomingData: Data
    ) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(path.utf8))
        for data in [workingData, baseData ?? Data(), currentData, incomingData] {
            hasher.update(data: Data([0]))
            hasher.update(data: data)
        }
        return hasher.finalize().map { byte in
            let value = String(byte, radix: 16)
            return value.count == 1 ? "0\(value)" : value
        }.joined()
    }

    private func containsConflictMarkers(_ text: String) -> Bool {
        text.split(separator: "\n", omittingEmptySubsequences: false).contains { line in
            line.hasPrefix("<<<<<<<") || line.hasPrefix("=======") || line.hasPrefix(">>>>>>>")
        }
    }
}
