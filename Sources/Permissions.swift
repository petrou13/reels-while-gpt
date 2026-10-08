import Foundation
import ApplicationServices

enum AXPermission {
    static var isGranted: Bool {
        // Check actual public API access too: trust may lag after a TCC preference change.
        let trusted = AXIsProcessTrusted()
        let root = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(root,0.15)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(root,kAXFocusedApplicationAttribute as CFString,&value)
        return evaluate(trusted:trusted,probe:result,hasValue:value != nil)
    }
    static func evaluate(trusted: Bool, probe: AXError, hasValue: Bool) -> Bool {
        if probe == .success && hasValue { return true }
        if probe == .apiDisabled { return false }
        return trusted
    }
}
