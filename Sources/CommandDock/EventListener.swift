import AppKit
import ApplicationServices
import CommandDockCore

final class EventListener {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var fallbackMouseMonitor: Any?
    private(set) var failureReason = ""
    private var recognizer = CommandTapRecognizer()
    private var router = OverlayKeyRouter()
    private var draining = false
    private var hasWorkingTap: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    var enabled: () -> Bool = { true }
    var visible: () -> Bool = { false }
    var active: () -> Bool = { false }
    var reveal: () -> Void = {}
    var bound: (UInt16) -> Bool = { _ in false }
    var overlayContains: (CGPoint) -> Bool = { _ in false }
    var maximumDuration: () -> Double = { 0.5 }
    var toggle: () -> Void = {}
    var dismiss: () -> Void = {}
    var outsideClick: () -> Void = {}
    var launch: (UInt16) -> Void = { _ in }
    var failed: () -> Void = {}

    @discardableResult func start() -> Bool {
        installLocalMonitor()
        draining = false
        resetGesture()
        router.reconcileHeldKeys { CGEventSource.keyState(.combinedSessionState, key: $0) }
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: true)
            failureReason = ""
            return CGEvent.tapIsEnabled(tap: tap)
        }
        // Ask Quartz itself whether keyboard events are available. A cached AX trust
        // result is not sufficient, and including mouse/flags in the probe can hide
        // missing keyboard permission because Quartz removes forbidden mask bits.
        let probeMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let probe = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: probeMask,
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) }, userInfo: nil) else {
            updateOverlayMonitoring()
            failureReason = "全局键盘权限尚未生效。若系统开关已开启，请移除旧的 CommandDock 条目，重新添加应用程序中的新版，再退出并重新启动。"
            return false
        }
        CFMachPortInvalidate(probe)
        let types: [CGEventType] = [.flagsChanged,.keyDown,.keyUp,.leftMouseDown,.rightMouseDown,.otherMouseDown,.leftMouseUp,.rightMouseUp,.otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info = info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<EventListener>.fromOpaque(info).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            failureReason = "全局键盘连接失败。请退出并重新启动 CommandDock，再检查辅助功能授权。"
            return false
        }
        if let monitor = fallbackMouseMonitor { NSEvent.removeMonitor(monitor); fallbackMouseMonitor = nil }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        failureReason = ""
        return CGEvent.tapIsEnabled(tap: newTap)
    }
    func stop(force: Bool = false) {
        // Keep the tap only long enough to swallow releases/repeats of keys whose
        // downs were swallowed. Pausing must not send orphan releases to an app.
        if !force && hasWorkingTap && router.hasConsumedKeys {
            draining = true
            recognizer.reset()
            return
        }
        draining = false
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; recognizer.reset()
        if let monitor = fallbackMouseMonitor { NSEvent.removeMonitor(monitor); fallbackMouseMonitor = nil }
        if !force && visible() { installFallbackMouseMonitor() }
    }
    func resetGesture() {
        let keys = Set((0..<128).map(UInt16.init).filter { CGEventSource.keyState(.combinedSessionState, key: $0) })
        let buttons = Set((0..<32).filter { CGEventSource.buttonState(.combinedSessionState, button: CGMouseButton(rawValue: UInt32($0))!) })
        recognizer.reset(heldKeys: keys, heldMouseButtons: buttons)
    }
    func prepareLocalSession() {
        guard !hasWorkingTap else { return }
        // Releases outside our app are unavailable to the local monitor.
        resetGesture()
        router.reconcileHeldKeys { CGEventSource.keyState(.combinedSessionState, key: $0) }
    }
    func updateOverlayMonitoring() {
        installLocalMonitor()
        if !hasWorkingTap && visible() {
            installFallbackMouseMonitor()
        } else if let monitor = fallbackMouseMonitor {
            NSEvent.removeMonitor(monitor)
            fallbackMouseMonitor = nil
        }
    }
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    private func installFallbackMouseMonitor() {
        guard fallbackMouseMonitor == nil else { return }
        fallbackMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self = self, self.visible(), let primary = NSScreen.screens.first else { return }
            let point = NSEvent.mouseLocation
            if !self.overlayContains(CGPoint(x: point.x, y: primary.frame.maxY - point.y)) { self.outsideClick() }
        }
    }
    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        // Quartz already routed events when its tap is enabled. The local path
        // is a fallback, and uses exactly the same action execution.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            return self.handleLocalEvent(event)
        }
    }
    func handleLocalEvent(_ event: NSEvent) -> NSEvent? {
        guard !hasWorkingTap else { return event }
        if event.type == .keyUp {
            recognizer.keyUp(event.keyCode)
            return router.keyUp(code: event.keyCode) == .consume ? nil : event
        }
        let flags = modifiers(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
        if event.type == .flagsChanged {
            guard active() else { return event }
            _ = recognizer.flagsChanged(keyCode: event.keyCode, modifiers: flags, time: event.timestamp)
            // Close on modifier-down, before the shortcut's next key is targeted.
            if !flags.isEmpty { recognizer.cancel(); dismiss() }
            return event
        }
        recognizer.keyDown(event.keyCode)
        return routeKey(code: event.keyCode, modifiers: flags, repeatKey: event.isARepeat) ? nil : event
    }
    private func routeKey(code: UInt16, modifiers: KeyModifiers, repeatKey: Bool) -> Bool {
        let isBound = bound(code)
        let action = router.keyDown(code: code, modifiers: modifiers, visible: active(), bound: isBound, repeatKey: repeatKey)
        let consumed = action.perform(dismiss: dismiss, launch: launch)
        // An unassigned key should show help immediately rather than leave the
        // user in an invisible input session.
        if action == .consume && active() && !visible() && !isBound && !repeatKey {
            reveal()
        }
        return consumed
    }
    private func modifiers(_ flags: CGEventFlags) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.maskCommand) { result.insert(.command) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskSecondaryFn) { result.insert(.function) }
        return result
    }
    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetGesture()
            router.reconcileHeldKeys { CGEventSource.keyState(.combinedSessionState, key: $0) }
            dismiss()
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tap = self.tap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) { self.stop(force: true); self.failed() }
                else if self.draining && !self.router.hasConsumedKeys { self.stop(force: true) }
            }
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            recognizer.keyUp(code)
            let consumed = router.keyUp(code: code) == .consume
            if draining && !router.hasConsumedKeys {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.draining else { return }
                    self.stop(force: true)
                    self.updateOverlayMonitoring()
                }
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        }
        if draining {
            if type == .keyDown && router.keyDown(code: code, modifiers: [], visible: false,
                bound: false, repeatKey: true) == .consume { return nil }
            return Unmanaged.passUnretained(event)
        }
        let flags = modifiers(event.flags)
        switch type {
        case .flagsChanged:
            recognizer.maximumDuration = maximumDuration()
            let trigger = recognizer.flagsChanged(keyCode: code, modifiers: flags,
                                                  time: Double(event.timestamp) / 1_000_000_000)
            if active() && !flags.isEmpty {
                recognizer.cancel()
                dismiss()
            } else if trigger && enabled() {
                // Arm synchronously so a following fast keyDown is never lost.
                // The delegate defers window presentation until after this event.
                toggle()
            }
            if !enabled() { recognizer.cancel() }
        case .keyDown:
            recognizer.keyDown(code)
            // Previously swallowed keys still own their repeats/releases even
            // after the session ends or triggering is temporarily disabled.
            if routeKey(code: code, modifiers: flags,
                repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0) { return nil }
        case .leftMouseDown,.rightMouseDown,.otherMouseDown:
            recognizer.mouseDown(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
            if active() && (!visible() || !overlayContains(event.location)) { outsideClick() }
        case .leftMouseUp,.rightMouseUp,.otherMouseUp:
            recognizer.mouseUp(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        default: break
        }
        return Unmanaged.passUnretained(event)
    }
    deinit {
        stop(force: true)
        if let localMonitor = localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
