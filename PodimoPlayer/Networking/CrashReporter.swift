import Foundation
import Darwin

// These handlers run in a crashing/signal context, where most Swift/Foundation
// APIs aren't safe to call. Everything they touch is either a raw C call or a
// value computed once up front — nothing is captured or allocated at crash time
// beyond what backtrace_symbols_fd itself needs.

private let exceptionLogPath: UnsafeMutablePointer<CChar> = strdup(
    (NSTemporaryDirectory() as NSString).appendingPathComponent("podimo_exception_crash.log")
)
private let signalLogPath: UnsafeMutablePointer<CChar> = strdup(
    (NSTemporaryDirectory() as NSString).appendingPathComponent("podimo_signal_crash.log")
)

// Pre-allocated once, well before any crash, so the signal handler never has
// to allocate memory itself (unsafe if the crash happened inside malloc).
private let backtraceCapacity = 128
private let backtraceBuffer = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: backtraceCapacity)

private func handleUncaughtException(_ exception: NSException) {
    let text = """
    \(exception.name.rawValue): \(exception.reason ?? "no reason")
    \(exception.callStackSymbols.joined(separator: "\n"))
    """
    try? text.write(toFile: String(cString: exceptionLogPath), atomically: true, encoding: .utf8)
}

private func handleFatalSignal(_ signalValue: Int32) {
    let fd = open(signalLogPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    if fd >= 0 {
        let frameCount = backtrace(backtraceBuffer, Int32(backtraceCapacity))
        backtrace_symbols_fd(backtraceBuffer, frameCount, fd)
        close(fd)
    }
    signal(signalValue, SIG_DFL)
    raise(signalValue)
}

/// Apple's documented technique (QA1361) for detecting an attached debugger.
private func isDebuggerAttached() -> Bool {
    var info = kinfo_proc()
    var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
    var size = MemoryLayout<kinfo_proc>.stride
    let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
    guard result == 0 else { return false }
    return (info.kp_proc.p_flag & P_TRACED) != 0
}

enum CrashReporter {
    private static let fatalSignals: [Int32] = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP]

    /// Installs handlers for uncaught NSExceptions and fatal signals (covers
    /// both Objective-C-style exceptions from frameworks like AVFoundation and
    /// Swift runtime traps like force-unwraps or out-of-bounds access) so a
    /// crash on this launch can be recorded and shown in Settings on the next one.
    /// Skipped while a debugger is attached (Xcode/LLDB already shows crashes
    /// directly, and a custom SIGTRAP/SIGILL handler would fight it for breakpoints).
    static func install() {
        guard !isDebuggerAttached() else { return }
        NSSetUncaughtExceptionHandler(handleUncaughtException)
        for signalValue in fatalSignals {
            signal(signalValue, handleFatalSignal)
        }
    }

    /// Picks up whatever a previous launch's crash handler wrote to disk (if
    /// anything) and feeds it into CrashLogStore. Call once, early, on launch.
    static func consumePendingCrash() {
        let exceptionURL = URL(fileURLWithPath: String(cString: exceptionLogPath))
        let signalURL = URL(fileURLWithPath: String(cString: signalLogPath))

        if let text = try? String(contentsOf: exceptionURL, encoding: .utf8), !text.isEmpty {
            CrashLogStore.shared.record(title: "Uncaught exception", detail: text)
        }
        try? FileManager.default.removeItem(at: exceptionURL)

        if let text = try? String(contentsOf: signalURL, encoding: .utf8), !text.isEmpty {
            CrashLogStore.shared.record(title: "Crash signal", detail: text)
        }
        try? FileManager.default.removeItem(at: signalURL)
    }
}
