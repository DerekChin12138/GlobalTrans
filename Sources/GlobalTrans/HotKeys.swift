import AppKit
import Carbon

enum HotKey {
    static let optionCommandO: UInt32 = UInt32(kVK_ANSI_O)
    static let modifiers: UInt32 = UInt32(optionKey | cmdKey)
    private static var registered = false

    static func register(handler: @escaping () -> Void) {
        guard !registered else { return }
        registered = true
        var eventHotKeyRef: EventHotKeyRef?
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let callback = Unmanaged<HotKeyBox>.fromOpaque(userData).takeUnretainedValue()
                callback.handler()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passRetained(HotKeyBox(handler: handler)).toOpaque(),
            nil
        )
        let hotKeyID = EventHotKeyID(signature: OSType(0x47544B31), id: 1)
        RegisterEventHotKey(
            optionCommandO,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &eventHotKeyRef
        )
    }
}

private final class HotKeyBox {
    let handler: () -> Void
    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
}
