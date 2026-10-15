import AppKit
import SwiftUI

final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func make(store: AppStore, delegate: NSWindowDelegate,
                     launch: @escaping (UInt16) -> Void, dismiss: @escaping () -> Void) -> LauncherPanel {
        let root = KeyboardView(store: store, launch: launch, dismiss: dismiss)
        let hosting = NSHostingView(rootView: root)
        let size = hosting.fittingSize
        let panel = LauncherPanel(contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.transient,.ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.delegate = delegate
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
}
