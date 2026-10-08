import AppKit
import SwiftUI
import Combine
import ApplicationServices
import CommandDockCore

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
    private var overlayApplication: NSRunningApplication?
    private var session = LauncherSession()
    private var presentation: DispatchWorkItem?
    private var sessionStartedAt: TimeInterval = 0
    private var measuringSession = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let identifier = Bundle.main.bundleIdentifier ?? "yunfenggroup.CommandDock"
        if NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        setupApplicationMenu()
        setupMenu()
        listener.enabled = { [weak self] in
            guard let self = self else { return false }
            return !self.store.paused && self.settingsWindow?.isKeyWindow != true && !self.showingError
        }
        listener.active = { [weak self] in self?.session.isActive == true }
        listener.reveal = { [weak self] in self?.schedulePresentation(delay: 0) }
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
        listener.outsideClick = { [weak self] in self?.hideOverlay(restoreFocus: false) }
        listener.launch = { [weak self] code in self?.launch(code) }
        listener.failed = { [weak self] in
            self?.store.listenerReady = false
            self?.store.listenerMessage = "全局监听已断开，请在设置中重新连接。"
        }
        store.$errorMessage.compactMap { $0 }.receive(on: RunLoop.main).sink { [weak self] message in
            self?.presentError(message)
        }.store(in: &subscriptions)
        store.$paused.dropFirst().sink { [weak self] paused in
            guard let self = self else { return }
            self.hideOverlay()
            if paused {
                self.listener.stop()
                self.store.listenerReady = false
                self.store.listenerMessage = "监听已暂停。"
            } else {
                // @Published emits before paused is updated; reconnect afterwards.
                DispatchQueue.main.async { [weak self] in self?.connectListener() }
            }
        }.store(in: &subscriptions)
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.listener.resetGesture(); self?.hideOverlay(restoreFocus: false)
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if let app = NSWorkspace.shared.frontmostApplication, self.session.isActive,
               app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               app.processIdentifier != self.overlayApplication?.processIdentifier {
                self.hideOverlay(restoreFocus: false)
            }
            if !self.store.listenerReady { self.connectListener() }
        })
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reconnect()
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.hideOverlay(restoreFocus: false)
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
        presentation?.cancel()
        listener.stop(force: true)
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
        beginSession(delay: 0, measure: false)
    }
    private func toggleOverlay() {
        if session.isActive {
            hideOverlay()
        } else {
            beginSession(delay: store.blindLaunchEnabled ? store.hintDelay : 0, measure: store.blindLaunchEnabled)
        }
    }
    private func beginSession(delay: Double, measure: Bool) {
        hideOverlay(restoreFocus: false)
        listener.prepareLocalSession()
        let front = NSWorkspace.shared.frontmostApplication
        overlayApplication = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApplication : front
        session.begin()
        sessionStartedAt = ProcessInfo.processInfo.systemUptime
        measuringSession = measure
        schedulePresentation(delay: delay)
    }
    private func schedulePresentation(delay: Double) {
        guard session.phase == .waiting else { return }
        presentation?.cancel()
        let token = session.presentationToken
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.session.phase == .waiting,
                  self.session.presentationToken == token else { return }
            // Workspace notifications can arrive after the timer. Recheck the
            // foreground app so a stale hint cannot steal focus even briefly.
            if let front = NSWorkspace.shared.frontmostApplication,
               front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
               front.processIdentifier != self.overlayApplication?.processIdentifier {
                self.hideOverlay(restoreFocus: false)
                return
            }
            guard self.session.reveal(token: token) else { return }
            self.presentation = nil
            self.showOverlay()
        }
        presentation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private func launch(_ code: UInt16) {
        hideOverlay(restoreFocus: false, launched: true)
        // Application lookup and launch stay outside Quartz's event callback.
        DispatchQueue.main.async { [weak self] in self?.store.launch(code) }
    }
    private func makeOverlay() -> LauncherPanel {
        let root = KeyboardView(store: store, launch: { [weak self] code in
            self?.launch(code)
        }, dismiss: { [weak self] in self?.hideOverlay() })
        let hosting = NSHostingView(rootView: root)
        let size = hosting.fittingSize
        let panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.transient,.ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        // Clip the material and hosting view together; backdrop layers can extend
        // beyond the visual effect view's own rounded layer.
        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.cornerRadius = 18; content.layer?.masksToBounds = true
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow; background.blendingMode = .behindWindow; background.state = .active
        background.maskImage = NSImage(size: size, flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18).fill()
            return true
        }
        background.autoresizingMask = [.width,.height]
        hosting.frame = content.bounds; hosting.autoresizingMask = [.width,.height]
        content.addSubview(background); content.addSubview(hosting); panel.contentView = content
        return panel
    }
    private func showOverlay() {
        if overlay == nil { overlay = makeOverlay() }
        guard let overlay = overlay,
              let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else {
            hideOverlay(restoreFocus: false)
            return
        }
        let area = screen.visibleFrame
        overlay.setFrameOrigin(NSPoint(x: area.midX - overlay.frame.width / 2, y: area.midY - overlay.frame.height / 2))
        overlay.makeKeyAndOrderFront(nil)
        listener.updateOverlayMonitoring()
    }
    private func hideOverlay(restoreFocus: Bool = true, launched: Bool = false) {
        let wasVisible = overlay?.isVisible == true
        let beforeHint = session.phase == .waiting
        if session.isActive && measuringSession {
            if launched {
                store.experiment.recordLaunch(beforeHint: beforeHint,
                    responseTime: ProcessInfo.processInfo.systemUptime - sessionStartedAt)
            } else { store.experiment.recordCancellation() }
        }
        session.end()
        presentation?.cancel(); presentation = nil
        measuringSession = false
        let previous = overlayApplication
        overlayApplication = nil
        overlay?.orderOut(nil)
        listener.updateOverlayMonitoring()
        if restoreFocus && wasVisible, let previous = previous, !previous.isTerminated,
           LauncherFocusPolicy.shouldRestore(previous: previous.processIdentifier,
               current: NSWorkspace.shared.frontmostApplication?.processIdentifier,
               launcher: ProcessInfo.processInfo.processIdentifier) {
            previous.activate(options: .activateIgnoringOtherApps)
        }
    }
    @objc private func showSettings() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = front
        }
        hideOverlay(restoreFocus: false); listener.resetGesture()
        store.refreshApplicationCache()
        if settingsWindow == nil {
            let view = SettingsView(store: store, retryPermission: { [weak self] in self?.reconnect() }, requestPermission: { [weak self] in self?.listener.requestPermission() }, preview: { [weak self] in self?.showFromMenu() }, resizeWindow: { [weak self] size in
                guard let window = self?.settingsWindow else { return }
                let top = window.frame.maxY
                window.setContentSize(size)
                window.setFrameOrigin(NSPoint(x: window.frame.minX, y: top - window.frame.height))
            })
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1039, height: 540),
                styleMask: [.titled,.closable,.miniaturizable], backing: .buffered, defer: false)
            window.title = "CommandDock 设置"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view); window.delegate = self; window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func reconnect() {
        hideOverlay()
        listener.stop(force: true)
        connectListener()
    }
    private func connectListener() {
        guard !store.paused else { return }
        let ready = listener.start()
        if store.listenerReady != ready { store.listenerReady = ready }
        if store.listenerMessage != listener.failureReason { store.listenerMessage = listener.failureReason }
    }
    @objc private func togglePause() { store.paused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    func windowWillClose(_ notification: Notification) { listener.resetGesture() }
    func windowDidResignKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === overlay, session.isActive {
            hideOverlay(restoreFocus: false)
        }
    }
    private func presentError(_ message: String) {
        guard !showingError else { return }
        hideOverlay(restoreFocus: false); showingError = true
        let alert = NSAlert(); alert.messageText = "CommandDock"; alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
        store.errorMessage = nil; showingError = false
    }
}
