@testable import Copythat
import AppKit
import Foundation
import Testing

private enum TerminationWorkerFailure: Error {
    case injectedSaveFailure
}

private actor TerminationSaveWorker: ClipboardHistorySaving {
    private(set) var attempts: [UInt64] = []
    private(set) var committedGenerations: [UInt64] = []
    private var committedText: String?
    private var blockedGenerations: Set<UInt64>
    private var failedGenerations: Set<UInt64>
    private var startWaiters: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var releaseWaiters: [UInt64: CheckedContinuation<Void, Never>] = [:]

    init(
        committedText: String? = nil,
        blockedGenerations: Set<UInt64> = [],
        failedGenerations: Set<UInt64> = []
    ) {
        self.committedText = committedText
        self.blockedGenerations = blockedGenerations
        self.failedGenerations = failedGenerations
    }

    func save(_ items: [ClipboardItem], generation: UInt64) async throws {
        attempts.append(generation)
        startWaiters.removeValue(forKey: generation)?.resume()
        if blockedGenerations.contains(generation) {
            await withCheckedContinuation { continuation in
                releaseWaiters[generation] = continuation
            }
        }
        if failedGenerations.remove(generation) != nil {
            throw TerminationWorkerFailure.injectedSaveFailure
        }
        committedText = items.first?.textValue
        committedGenerations.append(generation)
    }

    func collectGarbage() async {}

    func waitUntilStarted(_ generation: UInt64) async {
        if attempts.contains(generation) { return }
        await withCheckedContinuation { continuation in
            startWaiters[generation] = continuation
        }
    }

    func release(_ generation: UInt64) {
        blockedGenerations.remove(generation)
        releaseWaiters.removeValue(forKey: generation)?.resume()
    }

    func state() -> (attempts: [UInt64], committedGenerations: [UInt64], committedText: String?) {
        (attempts, committedGenerations, committedText)
    }
}

@MainActor
@Suite(.serialized)
struct AppDelegateTerminationTests {
    @Test func pendingLatestSaveCompletesNormalTermination() async {
        let worker = TerminationSaveWorker(blockedGenerations: [1])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = AppModel(historySaveCoordinator: coordinator)
        coordinator.requestSave([historyItem("latest")])
        await worker.waitUntilStarted(1)

        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .cancelQuit },
            replyToTermination: { replies.append($0) }
        )
        let response = delegate.applicationShouldTerminate(NSApplication.shared)

        #expect(response == .terminateLater)
        await worker.release(1)
        #expect(await waitUntil { replies.count == 1 })
        #expect(replies == [true])
        #expect(await worker.state().committedGenerations == [1])
    }

    @Test func retrySavesTheLatestStateBeforeReplyingToQuit() async {
        let worker = TerminationSaveWorker(committedText: "previously committed", failedGenerations: [2])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = AppModel(historySaveCoordinator: coordinator)
        coordinator.requestSave([historyItem("first")])
        #expect(await coordinator.flush())
        coordinator.requestSave([historyItem("latest")])

        var replies: [Bool] = []
        var choices: [ClipboardHistoryQuitChoice] = [.retry]
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { choices.removeFirst() },
            replyToTermination: { replies.append($0) }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)

        #expect(await waitUntil { replies.count == 1 })
        let state = await worker.state()
        #expect(replies == [true])
        #expect(state.attempts == [1, 2, 3])
        #expect(state.committedGenerations == [1, 3])
        #expect(state.committedText == "latest")
        #expect(choices.isEmpty)
    }

    @Test func quitAnywayKeepsPreviouslyCommittedHistory() async {
        let worker = TerminationSaveWorker(committedText: "previously committed", failedGenerations: [2])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = AppModel(historySaveCoordinator: coordinator)
        coordinator.requestSave([historyItem("committed")])
        #expect(await coordinator.flush())
        coordinator.requestSave([historyItem("unsaved")])

        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .quitAnyway },
            replyToTermination: { replies.append($0) }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)

        #expect(await waitUntil { replies.count == 1 })
        let state = await worker.state()
        #expect(replies == [true])
        #expect(state.committedGenerations == [1])
        #expect(state.committedText == "committed")
    }

    @Test func cancelQuitRepliesFalseAndAllowsAnotherQuitAttempt() async {
        let worker = TerminationSaveWorker(committedText: "previously committed", failedGenerations: [2])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = AppModel(historySaveCoordinator: coordinator)
        coordinator.requestSave([historyItem("committed")])
        #expect(await coordinator.flush())
        coordinator.requestSave([historyItem("unsaved")])

        var replies: [Bool] = []
        var choices = 0
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: {
                choices += 1
                return .cancelQuit
            },
            replyToTermination: { replies.append($0) }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        #expect(await waitUntil { replies.count == 1 })
        #expect(replies == [false])

        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        #expect(await waitUntil { replies.count == 2 })
        #expect(replies == [false, false])
        #expect(choices == 2)
        #expect(await worker.state().committedText == "committed")
    }

    @Test func terminationWaitsForAnewerGenerationInsteadOfAcceptingAnOlderSave() async {
        let worker = TerminationSaveWorker(blockedGenerations: [1, 2])
        let coordinator = ClipboardHistorySaveCoordinator(worker: worker)
        let model = AppModel(historySaveCoordinator: coordinator)
        coordinator.requestSave([historyItem("older")])
        await worker.waitUntilStarted(1)

        var replies: [Bool] = []
        let delegate = AppDelegate(
            model: model,
            chooseQuitSaveFailure: { .cancelQuit },
            replyToTermination: { replies.append($0) }
        )
        #expect(delegate.applicationShouldTerminate(NSApplication.shared) == .terminateLater)
        coordinator.requestSave([historyItem("newer")])
        await worker.release(1)
        await worker.waitUntilStarted(2)
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(replies.isEmpty)

        await worker.release(2)
        #expect(await waitUntil { replies.count == 1 })
        let state = await worker.state()
        #expect(replies == [true])
        #expect(state.committedGenerations == [1, 2])
        #expect(state.committedText == "newer")
    }

    private func historyItem(_ value: String) -> ClipboardItem {
        ClipboardItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000091")!,
            kind: .text,
            title: value,
            preview: value,
            sourceApp: "Tests",
            sourceAppIconData: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_091),
            isPinned: false,
            pinboardName: nil,
            textValue: value,
            fileURLs: [],
            imageData: nil
        )
    }

    private func waitUntil(
        timeout seconds: TimeInterval = 2,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return condition()
    }
}
