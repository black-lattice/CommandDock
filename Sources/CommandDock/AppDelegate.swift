import AppKit
import SwiftUI
import Combine
import ApplicationServices

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = AppStore()
    private let listener = EventListener()
    private var statusItem: NSStatusItem!
    private var overlay: LauncherPanel?
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var showingError = false
    private var previousApplication: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let identifier = Bundle.main.bundleIdentifier ?? "vip.haoduo.CommandDock"
        if NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        setupApplicationMenu()
        setupMenu()
        listener.enabled = { [weak self] in
            guard let self = self else { return false }
            return !self.store.paused && self.settingsWindow?.isKeyWindow != true && !self.showingError
        }
        listener.visible = { [weak self] in self?.overlay?.isVisible == true }
        listener.bound = { [weak self] code in self?.store.binding(for: code) != nil }
        listener.maximumDuration = { [weak self] in self?.store.tapDuration ?? 0.5 }
        listener.overlayContains = { [weak self] point in
            guard let frame = self?.overlay?.frame, let primary = NSScreen.screens.first else { return false }
            // Quartz uses a top-left origin; AppKit uses a bottom-left origin.
            return frame.contains(NSPoint(x: point.x, y: primary.frame.maxY - point.y))
        }
        listener.toggle = { [weak self] in self?.toggleOverlay() }
        listener.dismiss = { [weak self] in self?.hideOverlay() }
        listener.launch = { [weak self] code in self?.store.launch(code) }
        listener.failed = { [weak self] in
            self?.store.listenerReady = false
            self?.store.listenerMessage = "全局监听已断开，请在设置中重新连接。"
        }
        store.$errorMessage.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] message in
            self?.presentError(message)
        }.store(in: &subscriptions)
        store.$paused.dropFirst().sink { [weak self] _ in self?.listener.resetGesture(); self?.hideOverlay() }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.listener.resetGesture(); self?.hideOverlay()
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self, !self.store.listenerReady else { return }
            self.connectListener()
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.reconnect()
        })
        connectListener()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") || !store.listenerReady {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showSettings()
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if !store.listenerReady { connectListener() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings(); return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        listener.stop()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    private func setupApplicationMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let menu = NSMenu(title: "CommandDock")
        let settings = NSMenuItem(title: "CommandDock 设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 CommandDock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        appItem.submenu = menu
        bar.addItem(appItem)
        NSApp.mainMenu = bar
    }
    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "command", accessibilityDescription: "CommandDock")
        let menu = NSMenu()
        let title = NSMenuItem(title: "CommandDock", action: nil, keyEquivalent: "")
        title.isEnabled = false; menu.addItem(title)
        addItem("显示浮窗", action: #selector(showFromMenu), to: menu)
        addItem("应用绑定与设置…", action: #selector(showSettings), to: menu)
        menu.addItem(.separator())
        addItem("暂停 / 恢复监听", action: #selector(togglePause), to: menu)
        addItem("重新连接键盘监听", action: #selector(reconnect), to: menu)
        menu.addItem(.separator())
        addItem("退出 CommandDock", action: #selector(quit), to: menu)
        statusItem.menu = menu
    }
    private func addItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }
    @objc private func showFromMenu() {
        settingsWindow?.orderOut(nil)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication?.activate(options: .activateIgnoringOtherApps)
        }
        DispatchQueue.main.async { [weak self] in self?.showOverlay() }
    }
    private func toggleOverlay() {
        if overlay?.isVisible == true { hideOverlay() } else { showOverlay() }
    }
    private func makeOverlay() -> LauncherPanel {
        let root = KeyboardView(store: store, launch: { [weak self] code in
            self?.hideOverlay(); self?.store.launch(code)
        }, settings: { [weak self] in self?.showSettings() }, dismiss: { [weak self] in self?.hideOverlay() })
        let hosting = NSHostingView(rootView: root)
        let size = hosting.fittingSize
        let panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.transient,.ignoresCycle]
        panel.isReleasedWhenClosed = false
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow; background.blendingMode = .behindWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 18; background.layer?.masksToBounds = true
        hosting.frame = background.bounds; hosting.autoresizingMask = [.width,.height]
        background.addSubview(hosting); panel.contentView = background
        return panel
    }
    private func showOverlay() {
        if overlay == nil { overlay = makeOverlay() }
        guard let overlay = overlay,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame
        overlay.setFrameOrigin(NSPoint(x: area.midX - overlay.frame.width / 2, y: area.midY - overlay.frame.height / 2))
        overlay.makeKeyAndOrderFront(nil)
    }
    private func hideOverlay() { overlay?.orderOut(nil) }
    @objc private func showSettings() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = front
        }
        hideOverlay(); listener.resetGesture()
        if settingsWindow == nil {
            let view = SettingsView(store: store, retryPermission: { [weak self] in self?.reconnect() }, requestPermission: { [weak self] in self?.listener.requestPermission() }, preview: { [weak self] in self?.showFromMenu() })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
                styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
            window.title = "CommandDock 设置"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view); window.delegate = self; window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func reconnect() {
        listener.stop()
        connectListener()
    }
    private func connectListener() {
        let ready = listener.start()
        if store.listenerReady != ready { store.listenerReady = ready }
        if store.listenerMessage != listener.failureReason { store.listenerMessage = listener.failureReason }
    }
    @objc private func togglePause() { store.paused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { listener.resetGesture() }
    private func presentError(_ message: String) {
        guard !showingError else { return }
        hideOverlay(); showingError = true
        let alert = NSAlert(); alert.messageText = "CommandDock"; alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
        store.errorMessage = nil; showingError = false
    }
}
