import AppKit
import Carbon
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKeyManager: GlobalHotKeyManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        hotKeyManager = GlobalHotKeyManager {
            Task { @MainActor in await CaptureModel.shared.startCapture() }
        }
    }
}

final class PreviewWindowController: NSObject, NSWindowDelegate {
    static let shared = PreviewWindowController()
    private var window: NSWindow?

    @MainActor
    func show(model: CaptureModel, activate: Bool = true) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "RealMac"
            window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: ContentView(model: model))
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }
        if activate {
            window?.level = .normal
            NSApplication.shared.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.level = .floating
            window?.orderFrontRegardless()
        }
    }

    @MainActor func hideForCapture() { window?.orderOut(nil) }

    @MainActor
    func showSharePicker(for image: NSImage) {
        guard let view = window?.contentView else { return }
        NSSharingServicePicker(items: [image]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

private final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, pointer in
                guard let pointer else { return noErr }
                Unmanaged<GlobalHotKeyManager>.fromOpaque(pointer).takeUnretainedValue().action()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        let identifier = EventHotKeyID(signature: OSType(0x524D4143), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(cmdKey | shiftKey), identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
