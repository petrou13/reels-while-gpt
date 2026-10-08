import Foundation

// NSAppleScript is main-thread-only. A bundled helper keeps browser waits off the menu bar UI.
func encode(_ d: NSAppleEventDescriptor) -> [String: Any] {
    if d.descriptorType == 0x6c697374 { // 'list'
        return ["kind":"list", "value": (1...max(1,d.numberOfItems)).compactMap { d.atIndex($0).map(encode) }]
    }
    if [UInt32(0x6c6f6e67), UInt32(0x73686f72), UInt32(0x636f6d70)].contains(d.descriptorType) {
        return ["kind":"integer", "value":Int(d.int32Value)]
    }
    return ["kind":"string", "value":d.stringValue ?? ""]
}
let data = FileHandle.standardInput.readDataToEndOfFile()
guard let source = String(data:data,encoding:.utf8), let script = NSAppleScript(source:source) else { exit(2) }
var error: NSDictionary?
let result = script.executeAndReturnError(&error)
let response: [String:Any]
if let error { response = ["error":"browser-command-failed","code":error[NSAppleScript.errorNumber] as? Int ?? -1] }
else { response = ["result":encode(result)] }
if let output = try? JSONSerialization.data(withJSONObject:response) { FileHandle.standardOutput.write(output) }
exit(error == nil ? 0 : 1)
