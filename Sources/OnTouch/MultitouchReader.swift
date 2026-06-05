import Foundation
import CMultitouch
import IOKit.hid

/// Global C callback — a non-capturing function so it can be passed where a
/// C function pointer is expected. It simply forwards every frame to the engine.
private func mtFrameCallback(_ device: MTDeviceRef?,
                            _ touches: UnsafeMutablePointer<Finger>?,
                            _ numTouches: Int32,
                            _ timestamp: Double,
                            _ frame: Int32) -> Int32 {
    GestureEngine.shared.handleFrame(data: touches,
                                     count: Int(numTouches),
                                     timestamp: timestamp)
    return 0
}

/// Opens every multitouch device and streams frames to the gesture engine.
final class MultitouchReader {
    private var devices: [MTDeviceRef] = []

    /// True if at least one multitouch device started streaming.
    @discardableResult
    func start() -> Bool {
        // Ask for Input Monitoring up front (required on recent macOS to read
        // raw HID/multitouch data).
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)

        guard let list = MTDeviceCreateList()?.takeRetainedValue() else {
            NSLog("OnTouch: MTDeviceCreateList returned nil")
            return false
        }
        let count = CFArrayGetCount(list)
        for i in 0..<count {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = MTDeviceRef(mutating: raw)
            MTRegisterContactFrameCallback(device, mtFrameCallback)
            MTDeviceStart(device, 0)
            devices.append(device)
        }
        NSLog("OnTouch: started \(devices.count) multitouch device(s)")
        return !devices.isEmpty
    }

    func stop() {
        for device in devices {
            MTDeviceStop(device)
            MTUnregisterContactFrameCallback(device, mtFrameCallback)
        }
        devices.removeAll()
    }
}
