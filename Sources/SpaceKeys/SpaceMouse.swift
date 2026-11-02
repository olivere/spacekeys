import IOKit.hid
import SpaceKeysCore

/// Reports SpaceMouse button changes. The cap's motion axes are ignored.
///
/// The device is opened without seizing it, so other readers such as Space
/// Glider keep getting every report. IOHIDManager picks the device up again
/// after it sleeps or reconnects.
@MainActor
final class SpaceMouse {
    var onButton: (DeviceButton, Bool) -> Void = { _, _ in }
    var onConnected: (String) -> Void = { _ in }
    var onRemoved: () -> Void = {}

    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

    func start() throws {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x256F, // 3Dconnexion
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_MultiAxisController,
        ] as CFDictionary)

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == kHIDPage_Button else { return }
            let usage = Int(IOHIDElementGetUsage(element))
            let down = IOHIDValueGetIntegerValue(value) != 0
            let mouse = Unmanaged<SpaceMouse>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated {
                guard let button = DeviceButton(hidUsage: usage) else {
                    log("ignoring unknown button \(usage)")
                    return
                }
                mouse.onButton(button, down)
            }
        }, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "SpaceMouse"
            log("connected: \(name)")
            let mouse = Unmanaged<SpaceMouse>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { mouse.onConnected(name) }
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            log("disconnected")
            let mouse = Unmanaged<SpaceMouse>.fromOpaque(context!).takeUnretainedValue()
            MainActor.assumeIsolated { mouse.onRemoved() }
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            throw HIDError(code: result)
        }
    }

    /// The pid of a process holding a SpaceMouse exclusively, so that no
    /// button reports reach us, or nil.
    ///
    /// IOKit has no API for this. It reads the "ClientSeized" flag from the
    /// "DebugState" that each IOHIDLibUserClient publishes in the I/O
    /// Registry; if a macOS release drops that property, this returns nil.
    func exclusiveOwner() -> Int32? {
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return nil }
        for device in devices {
            let clients = Self.clients(of: IOHIDDeviceGetService(device))
            if let owner = SpaceKeysCore.exclusiveOwner(of: clients, me: getpid()) {
                return owner
            }
        }
        return nil
    }

    private static func clients(of service: io_service_t) -> [HIDClient] {
        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(service, kIOServicePlane, &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var clients: [HIDClient] = []
        while case let child = IOIteratorNext(iterator), child != 0 {
            defer { IOObjectRelease(child) }
            guard IOObjectConformsTo(child, "IOHIDLibUserClient") != 0,
                  let creator = property(child, "IOUserClientCreator") as? String,
                  let pid = HIDClient.pid(fromCreator: creator),
                  let state = property(child, "DebugState") as? [String: Any],
                  let seized = state["ClientSeized"] as? Bool
            else { continue }
            clients.append(HIDClient(pid: pid, seizedOut: seized))
        }
        return clients
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    struct HIDError: Error, CustomStringConvertible {
        let code: IOReturn
        var description: String { "cannot open the SpaceMouse (IOHIDManagerOpen 0x\(String(UInt32(bitPattern: code), radix: 16)))" }
    }
}
