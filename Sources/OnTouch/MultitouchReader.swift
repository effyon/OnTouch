import Foundation
import CMultitouch
import IOKit.hid

private enum MultitouchFrameDiagnostic {
    private static let lock = NSLock()
    private static var receivedFrame = false
    private static var lastContactCount: Int32 = -1

    static func reset() {
        lock.lock()
        receivedFrame = false
        lastContactCount = -1
        lock.unlock()
    }

    static func noteFrame(count: Int32) {
        lock.lock()
        let isFirstFrame = !receivedFrame
        let changedCount = lastContactCount != count
        receivedFrame = true
        lastContactCount = count
        lock.unlock()
        if isFirstFrame {
            Diagnostic.log("OnTouch: first multitouch callback frame received")
        }
        if changedCount { Diagnostic.log("OnTouch: raw contact count=\(count)") }
    }
}

/// Global C callback — a non-capturing function so it can be passed where a
/// C function pointer is expected. It simply forwards every frame to the engine.
private func mtFrameCallback(_ device: MTDeviceRef?,
                            _ touches: UnsafeMutablePointer<Finger>?,
                            _ numTouches: Int32,
                            _ timestamp: Double,
                            _ frame: Int32) -> Int32 {
    MultitouchFrameDiagnostic.noteFrame(count: numTouches)
    GestureEngine.shared.handleFrame(data: touches,
                                     count: Int(numTouches),
                                     timestamp: timestamp)
    return 0
}

/// Opens every multitouch device and streams frames to the gesture engine.
final class MultitouchReader {
    private var devices: [MTDeviceRef] = []

    var isRunning: Bool { devices.contains { MTDeviceIsRunning($0) } }

    /// True if at least one multitouch device started streaming.
    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        if !devices.isEmpty { stop() }
        GestureEngine.shared.reset()
        MultitouchFrameDiagnostic.reset()

        guard let list = MTDeviceCreateList()?.takeRetainedValue() else {
            Diagnostic.log("OnTouch: MTDeviceCreateList returned nil")
            return false
        }
        let count = CFArrayGetCount(list)
        var runningCount = 0
        Diagnostic.log("OnTouch: enumerated \(count) multitouch device(s)")
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = MTDeviceRef(mutating: raw)
            MTRegisterContactFrameCallback(device, mtFrameCallback)
            MTDeviceStart(device, 0)
            devices.append(device)
            let running = MTDeviceIsRunning(device)
            if running { runningCount += 1 }
            Diagnostic.log("OnTouch: multitouch device \(i + 1)/\(count) running immediately after start=\(running)")
        }
        Diagnostic.log("OnTouch: registered \(devices.count) multitouch device(s); running immediately after start=\(runningCount)")
        return isRunning
    }

    func stop() {
        let count = devices.count
        for device in devices {
            MTDeviceStop(device)
            MTUnregisterContactFrameCallback(device, mtFrameCallback)
        }
        devices.removeAll()
        GestureEngine.shared.reset()
        if count > 0 { Diagnostic.log("OnTouch: stopped \(count) multitouch device(s)") }
    }
}
