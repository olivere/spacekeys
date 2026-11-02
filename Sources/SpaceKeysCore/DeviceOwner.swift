/// One process that has the HID device open, as the I/O Registry lists it.
public struct HIDClient: Equatable, Sendable {
    public let pid: Int32
    /// True while another client holds the device exclusively. The holder
    /// itself reads false.
    public let seizedOut: Bool

    public init(pid: Int32, seizedOut: Bool) {
        self.pid = pid
        self.seizedOut = seizedOut
    }

    /// Reads the registry's "IOUserClientCreator" value, "pid 7608, SpaceJuggler".
    public static func pid(fromCreator creator: String) -> Int32? {
        guard creator.hasPrefix("pid ") else { return nil }
        return Int32(creator.dropFirst(4).prefix { $0.isNumber })
    }
}

/// The process holding the device exclusively, or nil while we can read it.
/// Only meaningful when `me` is among the clients; a seize leaves every other
/// client seized out, so the holder is the one that is not.
public func exclusiveOwner(of clients: [HIDClient], me: Int32) -> Int32? {
    guard let mine = clients.first(where: { $0.pid == me }), mine.seizedOut else { return nil }
    return clients.first { $0.pid != me && !$0.seizedOut }?.pid
}

/// The name to show for a process: a helper inside another app's bundle
/// (Kugelblitz.app/Contents/Helpers/Space Juggler.app) is named after the
/// outermost app, since that is the one the user knows.
public func displayName(forExecutablePath path: String) -> String? {
    guard let bundle = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) else { return nil }
    return String(bundle.dropLast(4))
}
