import AppKit
import Sparkle

final class AppUpdater: NSObject, SPUStandardUserDriverDelegate {
    private let item = NSMenuItem()
    private let statusItem: NSStatusItem
    private let standardImage: NSImage?
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self
    )

    init?(menu: NSMenu, statusItem: NSStatusItem) {
        // The standalone SwiftPM executable has no update feed or app bundle to replace.
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return nil }
        self.statusItem = statusItem
        standardImage = statusItem.button?.image
        super.init()
        item.title = "检查更新…"
        item.target = controller
        item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        menu.addItem(item)
        controller.startUpdater()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        item.title = "更新到 \(update.displayVersionString)…"
        statusItem.button?.image = NSImage(systemSymbolName: "command.circle.fill", accessibilityDescription: "CommandDock 有可用更新")
    }

    func standardUserDriverWillFinishUpdateSession() {
        item.title = "检查更新…"
        statusItem.button?.image = standardImage
    }
}
