//
//  UpdateService.swift
//  RingBreak
//
//  Minimal Sparkle wrapper for auto-updates.
//

import Foundation
import Sparkle

final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    enum State: Equatable {
        case idle
        case checking
        case available(version: String)
        case upToDate
    }

    @Published private(set) var state: State = .idle

    private var updaterController: SPUStandardUpdaterController?

    var canCheckForUpdates: Bool {
        updaterController != nil
    }

    override private init() {
        super.init()

        guard let feedURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              !feedURL.isEmpty else {
            return
        }

        self.updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func start() {
        updaterController?.startUpdater()
    }

    func checkForUpdates() {
        guard let updaterController else { return }
        state = .checking
        updaterController.checkForUpdates(nil)
    }
}

// MARK: - SPUUpdaterDelegate

extension UpdateService: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in
            state = .available(version: item.displayVersionString)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in
            state = .upToDate
        }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            state = .upToDate  // Fail silently, appear as "no update"
        }
    }
}
