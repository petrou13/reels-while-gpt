import Foundation
import Darwin

/// A kernel lock survives path aliases/copies and is released automatically when the process exits.
final class SingleInstanceLock {
    private let descriptor: Int32
    init?(path: String) {
        let fd = open(path,O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC,mode_t(0o600))
        guard fd >= 0 else { return nil }
        guard flock(fd,LOCK_EX | LOCK_NB) == 0 else { close(fd); return nil }
        descriptor=fd
    }
    deinit { flock(descriptor,LOCK_UN); close(descriptor) }
    static var applicationPath: String {
        (NSTemporaryDirectory() as NSString).appendingPathComponent("ReelsWhileGPT-\(getuid()).lock")
    }
}
