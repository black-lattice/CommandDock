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
    var enabled: () -> Bool = { true }
    var visible: () -> Bool = { false }
    var bound: (UInt16) -> Bool = { _ in false }
    var overlayContains: (CGPoint) -> Bool = { _ in false }
    var maximumDuration: () -> Double = { 0.5 }
    var toggle: () -> Void = {}
    var dismiss: () -> Void = {}
    var launch: (UInt16) -> Void = { _ in }
    var failed: () -> Void = {}

    @discardableResult func start() -> Bool {
        installLocalMonitor()
        if let tap = tap {
            CGEvent.tapEnable(tap: tap, enable: true)
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
            installFallbackMouseMonitor()
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
    func stop() {
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; recognizer.reset(); router.reset()
        if let monitor = fallbackMouseMonitor { NSEvent.removeMonitor(monitor); fallbackMouseMonitor = nil }
    }
    func resetGesture() { recognizer.reset() }
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
            if !self.overlayContains(CGPoint(x: point.x, y: primary.frame.maxY - point.y)) { self.dismiss() }
        }
    }
    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        // The panel must remain keyboard-operable even before global permission is
        // granted. A filtering tap consumes its routed events before this monitor,
        // so the two paths do not launch an application twice.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .keyUp {
                if self.tap == nil { self.recognizer.keyUp(event.keyCode) }
                return self.router.keyUp(code: event.keyCode) == .consume ? nil : event
            }
            guard self.visible() else { return event }
            let flags = self.modifiers(CGEventFlags(rawValue: UInt64(event.modifierFlags.rawValue)))
            if event.type == .flagsChanged {
                if self.tap == nil {
                    _ = self.recognizer.flagsChanged(keyCode: event.keyCode, modifiers: flags, time: event.timestamp)
                }
                // Restore keyboard focus on modifier-down, before the next keyDown
                // is targeted, so a system shortcut goes to the previous app.
                if !flags.isEmpty { self.recognizer.cancel(); self.dismiss() }
                return event
            }
            if self.tap == nil { self.recognizer.keyDown(event.keyCode) }
            switch self.router.keyDown(code: event.keyCode, modifiers: flags, visible: true,
                                      bound: self.bound(event.keyCode), repeatKey: event.isARepeat) {
            case .launch(let code):
                self.dismiss()
                DispatchQueue.main.async { [weak self] in self?.launch(code) }
                return nil
            case .dismiss, .dismissAndPassThrough:
                self.dismiss()
                return nil
            case .consume: return nil
            case .passThrough: return event
            }
        }
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
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            recognizer.reset()
            router.reset()
            dismiss()
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tap = self.tap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) { self.stop(); self.failed() }
            }
            return Unmanaged.passUnretained(event)
        }
        let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .keyUp {
            recognizer.keyUp(code)
            if router.keyUp(code: code) == .consume { return nil }
        }
        guard enabled() else { recognizer.reset(); return Unmanaged.passUnretained(event) }
        let flags = modifiers(event.flags)
        switch type {
        case .flagsChanged:
            recognizer.maximumDuration = maximumDuration()
            let trigger = recognizer.flagsChanged(keyCode: code, modifiers: flags,
                                                  time: Double(event.timestamp) / 1_000_000_000)
            if visible() && !flags.isEmpty {
                recognizer.cancel()
                dismiss()
            } else if trigger {
                // Complete the system modifier event before presenting the panel.
                DispatchQueue.main.async { [weak self] in if self?.enabled() == true { self?.toggle() } }
            }
        case .keyDown:
            recognizer.keyDown(code)
            let action = router.keyDown(code: code, modifiers: flags, visible: visible(), bound: bound(code),
                                       repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
            switch action {
            case .passThrough: break
            case .dismissAndPassThrough: dismiss()
            case .consume: return nil
            case .dismiss: dismiss(); return nil
            case .launch(let code):
                dismiss()
                DispatchQueue.main.async { [weak self] in self?.launch(code) }
                return nil
            }
        case .leftMouseDown,.rightMouseDown,.otherMouseDown:
            recognizer.mouseDown(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
            if visible() && !overlayContains(event.location) { dismiss() }
        case .leftMouseUp,.rightMouseUp,.otherMouseUp:
            recognizer.mouseUp(Int(event.getIntegerValueField(.mouseEventButtonNumber)))
        default: break
        }
        return Unmanaged.passUnretained(event)
    }
    deinit {
        stop()
        if let localMonitor = localMonitor { NSEvent.removeMonitor(localMonitor) }
    }
}
