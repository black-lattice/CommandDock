import AppKit
import ApplicationServices
import CommandDockCore

final class EventListener {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
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
        if let tap = tap { return CGEvent.tapIsEnabled(tap: tap) }
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.flagsChanged,.keyDown,.keyUp,.leftMouseDown,.rightMouseDown,.otherMouseDown,.leftMouseUp,.rightMouseUp,.otherMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
                guard let info = info else { return Unmanaged.passUnretained(event) }
                return Unmanaged<EventListener>.fromOpaque(info).takeUnretainedValue().handle(type, event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }
    func stop() {
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap = tap { CFMachPortInvalidate(tap) }
        source = nil; tap = nil; recognizer.reset(); router.reset()
    }
    func resetGesture() { recognizer.reset() }
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
            if recognizer.flagsChanged(keyCode: code, modifiers: flags,
                                       time: Double(event.timestamp) / 1_000_000_000) {
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
    deinit { stop() }
}
